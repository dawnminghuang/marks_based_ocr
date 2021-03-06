function text = print_ocr_rec_acc_report(line_nums, Comps, Syms, map, ...
                                         gt_file, varargin)
%  PRINT_OCR_REC_ACC_REPORT  Display OCR accuracy reports
%
%   print_ocr_rec_acc_report(line_nums, Comps, Syms, map, gt_file)
%
%   line_nums should be a vector listing valid line numbers to be printed (in
%   the order they are to be printed).  Any invalid lines are skipped when
%   printed to the screen (an empty string is saved to text for that entry)
%
%   Comps is the comp struct like that returned in get_comps()
%
%   Syms is the symbol structure.  See create_alphabet()
%
%   map is a learned cluster to symbol index map vector.  For each cluster, the
%   index of the mapped symbol is returned.  This can be found by running
%   learn_mappings() or srilm_learn_mappings()
%
%   gt_file should be the path and name of a file containing the corresponding 
%   ground-truth text, used to generate the report
%
%   text returned will be a cell array, with one entry per report, each of
%   which will be a character array containing the report text.  By 
%   default, the report is also printed to the screen (though this 
%   can be overridden)
%

% CVS INFO %
%%%%%%%%%%%%
% $Id: print_ocr_rec_acc_report.m,v 1.2 2007-05-14 23:18:16 scottl Exp $
%
% REVISION HISTORY
% $Log: print_ocr_rec_acc_report.m,v $
% Revision 1.2  2007-05-14 23:18:16  scottl
% added ability to generate reports ignoring case of characters.
%
% Revision 1.1  2007-05-08 01:00:46  scottl
% initial check-in
%


% LOCAL VARS %
%%%%%%%%%%%%%%

%which reports should we generate?
gen_char_acc_rprt = true;
gen_word_acc_rprt = false;
gen_per_clust_acc_rprt = false;
gen_ig_case_char_acc_rprt = false;
gen_ig_case_word_acc_rprt = false;

%set save_results to true to write the results to disk based on the params
%below it
save_results = false;
global MOCR_PATH;  %make use of the globally defined MOCR_PATH variable
save_res_prefix = [MOCR_PATH, '/results/ocr_text_res'];
save_char_res_suffix = '.char_rprt';
save_word_res_suffix = '.word_rprt';
save_clust_res_suffix = '.clust_rprt';
save_ig_case_char_res_suffix = '.ig_case_char_rprt';
save_ig_case_word_res_suffix = '.ig_case_word_rprt';

%should we save the generated text file too?
save_gen_text = false;
save_gen_file = '/tmp/ocr_gen.txt';

display_text = true;  %print the report(s) to the terminal?

%this is used to further limit the components returned to those that lie 
%entirely within the contained LTRB region on each page.  This is only really
%useful if all lines to process lie on the same page (as the same regions are
%used on each page.  Use a value of 0 to represent one of the extremities of 
%the page
keep_region = [0 0 0 0];

%this parameter controls which clusters are printed and reported against.  
%Setting it to 0, will generate the accuracy reports based on all clusters, 
%setting it to a positive value of at least 1 defines a threshold stating how 
%many components that cluster must have to be used.  Setting it to a fractional %value strictly between 0 and 1 indicates the percentage of total components 
%that this cluster must make up to be included
inclusion_thresh = 0;

%select the symbol that will be generated for clusters who are not to be 
%included in the recognition accuracy reports.  This is required so that the 
%ground truth text can be aligned and have its corresponding symbols removed 
%before recognition occurs
delete_sym = '~';

%if we have to modify the ground truth, where should we store this file
save_mod_gt = false;
mod_gt_file = '/tmp/mod_gt.txt';

%where should we write the sync file temporarily?
tmp_sync_file = '/tmp/ocr_sync.txt';

tmp_ig_case_file = '/tmp/ig_case.txt';
tmp_ig_case_gt_file = '/tmp/ig_case_gt.txt';


% CODE START %
%%%%%%%%%%%%%%
tic;

if nargin < 5
    error('incorrect number of arguments specified!');
elseif nargin > 5
    process_optional_args(varargin{:});
end

%first, generate the output text based on region info and inclusion thresh
keep_clust = true(max(Comps.clust),1);
if inclusion_thresh ~= 0
    if inclusion_thresh < 1
        inclusion_thresh = inclusion_thresh*Comps.max_comp;
    end
    for ii=1:length(keep_clust)
        if sum(Comps.clust == ii) < inclusion_thresh
            keep_clust(ii) = false;
        end
    end
    if ~all(keep_clust)
        idx = find(strcmp(Syms.val, delete_sym));
        if isempty(idx)
            Syms.val{Syms.num+1} = delete_sym;
            Syms.num = Syms.num+1;
            idx = Syms.num;
        end
        map(~keep_clust) = idx;
    end
end

print_ocr_text(line_nums, Comps, Syms, map, ...
               'display_text', false, 'save_results', true, ...
               'keep_region', keep_region, ...
               'save_file', save_gen_file);

%sync the generated text and ground-truth to determine per cluster accuracies, 
%or remove unwanted symbols
if ~all(keep_clust) || gen_per_clust_acc_rprt
    cmd = ['cp ', gt_file, ' ', mod_gt_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running cp. cmd: %s', cmd);
    end
    cmd = ['synctext ', mod_gt_file, ' ', save_gen_file, ' > ', tmp_sync_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running synctext. cmd: %s', cmd);
    end
    %synctext produces a rather byzantine output that starts with
    %the aligned common text sandwiched between two rows of equals signs, then
    %places where each input is distinct are marked with a number between two
    %brace symbols ex. {4} After the second equals sign, each pair of rows lists
    %the differences between the files at a particular numbered point.  A row of
    %equal signs delimits this output.  Here's a small sample (with rows of 
    %equals symbols truncated -- there should be 79 per row):
    %
    %===================================================
    %
    %{1}n the event that {2}an{3}lor{4} claims that...
    %
    %===================================================
    %{1}
    %9460_004.Z01.gt.txt {I}
    %9460_004.Z01        {~}
    %===================================================
    %{2}
    %9460_004.Z01.gt.txt {L}
    %9460_004.Z01        {~.}
    %===================================================

    new_gen_txt = '';
    new_gt_txt = '';
    fid = fopen(tmp_sync_file);
    S = textscan(fid, '%[^\n]');
    fclose(fid);
    delete(tmp_sync_file);
    S = S{1};
    eq_rows = find(strcmp(S,repmat('=',1,79)));
    num_diffs = length(eq_rows)-2;
    gen_reps = cell(num_diffs,1);
    gt_reps = cell(num_diffs,1);
    for ii=1:num_diffs
        gt_row = eq_rows(ii+1)+2;
        gen_row = eq_rows(ii+1)+3;
        if eq_rows(ii+2) ~= gt_row+2
            %in this case at least one of the ground truth or generated text is 
            %split over multiple lines
            start_row = gt_row+1;
            while S{start_row}(1) ~= S{gt_row}(1)
                %join this row with the first row
                S{gt_row} = [S{gt_row}, strtrim(S{start_row})];
                start_row = start_row+1;
            end
            gen_row = start_row;
            start_row = start_row+1;
            while start_row < eq_rows(ii+2)
                S{gen_row} = [S{gen_row}, strtrim(S{start_row})];
                start_row = start_row+1;
            end
        end
        gt_reps{ii} = regexp(S{gt_row}, '\{(.*)\}', 'tokens');
        gt_reps{ii} = strtrim(gt_reps{ii}{1}{1});
        gen_reps{ii} = regexp(S{gen_row}, '\{(.*)\}', 'tokens');
        gen_reps{ii} = strtrim(gen_reps{ii}{1}{1});
        
        if ~all(keep_clust)
            %remove occurences of the delete_sym (and its associated ground 
            %truth symbol to ensure that we don't count mis-alignments there)
            trunc_pos = strfind(gen_reps{ii}, delete_sym);
            gt_reps{ii} = gt_reps{ii}(setdiff(1:length(gt_reps{ii}),trunc_pos));
            gen_len = length(gen_reps{ii});
            trunc_pos = trunc_pos(trunc_pos <= gen_len);
            gen_reps{ii} = gen_reps{ii}(setdiff(1:gen_len,trunc_pos));
        end
    end
    %now that we have our sets of replacement text, parse the sync'ed text 
    %looking for places to insert our replacements
    for ii=eq_rows(1)+1:eq_rows(2)-1
        new_gen_txt = [new_gen_txt, S{ii}, char(10)];
    end
    new_gt_txt = new_gen_txt;

    if gen_per_clust_acc_rprt
        clust_seq = get_cluster_seq(Comps, line_nums, 'keep_region', ...
                    keep_region);
        %have to be careful of empty lines returned from the cluster sequence
        idx = true(size(clust_seq,1),1);
        for jj=1:length(idx)
            if isempty(clust_seq{jj})
                idx(jj) = false;
            end
        end
        clust_seq = cell2mat(clust_seq(idx));
        clust_corr = false(size(clust_seq));
        sync_pos = 1;
        corr_pos = 1;
        diff_pos = 1;
        while sync_pos <= length(new_gen_txt) && corr_pos <= length(clust_seq)
            val = Syms.val{map(clust_seq(corr_pos))};
            if val == new_gen_txt(sync_pos)
                %correct match
                clust_corr(corr_pos) = true;
                corr_pos = corr_pos+1;
                sync_pos = sync_pos+1;
            elseif double(new_gen_txt(sync_pos)) == 10 || ...
                   new_gen_txt(sync_pos) == ' ' || new_gen_txt(sync_pos) == '^'
                %end of line or space or suspct character found
                sync_pos = sync_pos+1;
            elseif val == '^' || val == ' '
                %trim spaces and 'suspect' markers
                clust_corr(corr_pos) = true;
                corr_pos=corr_pos+1;
            elseif diff_pos <= num_diffs && new_gen_txt(sync_pos) == '{'
                %start of mismatch with ground truth (mismatch can be one-to-one
                %many-to-one, or one-to-many and may contain additional spaces)
                gen = gen_reps{diff_pos};
                while ~isempty(gen)
                    if gen(1) ~= Syms.val{map(clust_seq(corr_pos))}
                        while corr_pos <= length(clust_seq) && ...
                              (Syms.val{map(clust_seq(corr_pos))} == ' ' || ...
                               Syms.val{map(clust_seq(corr_pos))} == '^')
                            corr_pos=corr_pos+1;
                        end
                        while(length(gen) > 1 && (gen(1)==' ' || gen(1)=='^'))
                            gen = gen(2:end);
                        end
                    end
                    gen = gen(2:end);
                    corr_pos=corr_pos+1;
                end
                diff_pos=diff_pos+1;
                while sync_pos <= length(new_gen_txt) && ...
                      new_gen_txt(sync_pos) ~= '}'
                    sync_pos=sync_pos+1;
                end
                sync_pos=sync_pos+1;  %skip over the '}'
            else
                %should never reach here!
                keyboard
                error('problem parsing sync text');
            end
        end
    end
    expr = cell(num_diffs,1);
    for ii=1:num_diffs
        expr{ii} = ['{', num2str(ii), '}'];
    end
    new_gen_txt = regexprep(new_gen_txt, expr, gen_reps);
    new_gt_txt = regexprep(new_gt_txt, expr, gt_reps);
    fid = fopen(mod_gt_file, 'w');
    fwrite(fid,new_gt_txt);
    fclose(fid);
    fid = fopen(save_gen_file, 'w');
    fwrite(fid,new_gen_txt);
    fclose(fid);

    gt_file = mod_gt_file;
end

%generate the reports
text = cell(0);
if gen_char_acc_rprt
    cmd = ['accuracy ', gt_file, ' ', ...
           save_gen_file, ' ', save_res_prefix, save_char_res_suffix];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end
    fid = fopen([save_res_prefix, save_char_res_suffix]);
    S = fread(fid);
    if display_text
        fprintf('%c',S);
    end
    fclose(fid);
    text{end+1} = char(S');
    if ~save_results
        delete([save_res_prefix, save_char_res_suffix]);
    end
end

if gen_word_acc_rprt
    cmd = ['wordacc ', gt_file, ' ', ...
           save_gen_file, ' ', save_res_prefix, save_word_res_suffix];
    s = unix(cmd);
    if s ~= 0
        error('prob running word accuracy. cmd: %s', cmd);
    end
    fid = fopen([save_res_prefix, save_word_res_suffix]);
    S = fread(fid);
    if display_text
        fprintf('%c',S);
    end
    fclose(fid);
    text{end+1} = char(S');
    if ~save_results
        delete([save_res_prefix, save_word_res_suffix]);
    end
end

if gen_per_clust_acc_rprt
    %generate a 3 column table, where the first column
    %is the cluster number (ordered by frequency)
    %the second is the number of occurences of that cluster
    %and the third, the number of occurences correctly identified
    %(note that multiple spaces may be truncated when aligned, but consecutive 
    %spaces are all counted as correct in such a situation)
    max_clust = max(clust_seq);
    res = zeros(max_clust,3);
    if ~isempty(clust_seq)
        res(:,1) = 1:max_clust;
        for ii=1:max_clust
            idx = find(clust_seq == ii);
            if ~isempty(idx)
                res(ii,2) = length(idx);
                res(ii,3) = sum(clust_corr(idx));
            end
        end
    end
    text{end+1} = res;
    if save_results
        fid = fopen([save_res_prefix, save_clust_res_suffix], 'w');
        fprintf(fid, '%d %d %d\n', res');
        fclose(fid);
    end
end

if gen_ig_case_char_acc_rprt
    %convert both the generated text and ground truth to all lowercase
    cmd = ['tr [:upper:] [:lower:] < ', save_gen_file, ' > ', tmp_ig_case_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end
    cmd = ['tr [:upper:] [:lower:] < ', gt_file, ' > ', tmp_ig_case_gt_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end

    cmd = ['accuracy ', tmp_ig_case_gt_file, ' ', ...
           tmp_ig_case_file, ' ', save_res_prefix,save_ig_case_char_res_suffix];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end
    fid = fopen([save_res_prefix, save_ig_case_char_res_suffix]);
    S = fread(fid);
    if display_text
        fprintf('%c',S);
    end
    fclose(fid);
    text{end+1} = char(S');
    if ~save_results
        delete([save_res_prefix, save_ig_case_char_res_suffix]);
    end
end

if gen_ig_case_word_acc_rprt
    %convert both the generated text and ground truth to all lowercase
    cmd = ['tr [:upper:] [:lower:] < ', save_gen_file, ' > ', tmp_ig_case_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end
    cmd = ['tr [:upper:] [:lower:] < ', gt_file, ' > ', tmp_ig_case_gt_file];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end

    cmd = ['wordacc ', tmp_ig_case_gt_file, ' ', ...
           tmp_ig_case_file, ' ', save_res_prefix,save_ig_case_word_res_suffix];
    s = unix(cmd);
    if s ~= 0
        error('prob running accuracy. cmd: %s', cmd);
    end
    fid = fopen([save_res_prefix, save_ig_case_word_res_suffix]);
    S = fread(fid);
    if display_text
        fprintf('%c',S);
    end
    fclose(fid);
    text{end+1} = char(S');
    if ~save_results
        delete([save_res_prefix, save_ig_case_word_res_suffix]);
    end
end

if ~save_gen_text
    delete(save_gen_file);
end
if ~all(keep_clust) && ~save_mod_gt
    delete(mod_gt_file);
end
