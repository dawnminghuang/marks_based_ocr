%this script will attempt to use the ground truth text from the UNLV ISRI OCR
%'B' dataset, to create clusters, then attempt to infer the labels, and save
%the accuracy results.  Symbol values and clusters are normalized by position
%instead of overall count.

global MOCR_PATH;  %used to determine where to save results

%set the following line to true to record process
create_diary = true;
if create_diary
    diary_file = [MOCR_PATH, ...
    '/results/unlv_LGTposnorm_15_simweight_restricted_density_long.diary'];
    if exist(diary_file)
        delete(diary_file);
    end
    diary(diary_file);
    diary on;
    fprintf('EXPERIMENT STARTED: %s\n', datestr(now));
end

run_cluster=true;
run_pos_map=true;
run_word_map=true;
run_ocr_analysis=true;
run_alt_acc=true;

%if attempting to determine mappings, this should list the file containing the
%Syms corpora struct
syms_struct_file = [MOCR_PATH, '/data/reuters_pos_15_syms.mat'];

%this directory determines where to find the ASCII text pages
pg_dir = [MOCR_PATH, '/data/unlv_ocr/L/L_GT/'];

%this should give the path to the base part of where results will be kept
res_base = [MOCR_PATH, '/results/LGTposnorm_15_simweight_restricted_density_long'];
if ~exist(res_base, 'dir')
    [s,w] = unix(['mkdir -p ', res_base]);
    if s~=0
        error('problem creating dir: %s', res_base);
    end
end

%open and read the list of pages from the pg_file
xx = dir(pg_dir);
imgs = cell(length(xx),1);
[imgs{:}] = deal(xx.name);
imgs = imgs(3:end);  %remove . and ..
docs = unique(regexprep(imgs, '(\w*)\_.*', '$1'));
%@@quick hack to get the long docs only
docs = docs(end-9:end);
num_docs = length(docs);

%ensure that if we are doing mappings or analysis, the struct file can be loaded
if run_pos_map || run_word_map || run_ocr_analysis
    load(syms_struct_file);
end

%setup counts for each symbol type
if run_alt_acc
    t = [];
    l = [];
    u = [];
    d = [];
    o = [];
    s = [];
end

tic;
for ii=1:num_docs
    fprintf('%.2f: Processing document: %s\n', toc, docs{ii});
    res_dir = [res_base, '/', docs{ii}];
    if ~exist(res_dir, 'dir')
        fprintf('%.2f: Creating new dir\n', toc);
        [s,w] = unix(['mkdir -p ', res_dir]);
        if s~=0
            warning('MBOCR:NoDir', 'problem creating dir: %s\n', res_dir);
            continue;
        end
    end

    res_datafile = [res_dir, '/data.mat'];
    idx = strmatch(docs{ii}, imgs);
    Files = regexprep(imgs(idx), '(.*)', [pg_dir, '$1']);

    %now cluster the components
    if run_cluster
        [Clust, Comps, Lines] = create_text_clusters(Files, 'max_word_len', 15);
        %now renormalize positional counts
        for jj=1:length(Clust.pos_count);
            val = Clust.pos_count{jj} .* Clust.pos_total;
            norms = sum(val,2);
            norms(norms == 0) = 1;  %to prevent dividing by 0
            Clust.pos_norms{jj} = repmat(norms, 1, size(val,2));
            Clust.pos_count{jj} = val ./ Clust.pos_norms{jj};
        end
        save(res_datafile, 'Clust', 'Comps', 'Lines');
        fprintf('clustering complete: %f\n', toc);
    end

    load(res_datafile);

    %now attempt to infer mappings based on positional information
    if run_pos_map
        [order, score] = positional_learn_mappings(Clust, Syms, ...
                         'dist_metric', 'euc', 'weight_proportion', 0.85, ...
                         'prior_counts', 0, 'weight_per_symbol', false);
        fprintf('position based ordering complete: %f\n', toc);
        save(res_datafile, 'Clust', 'Comps', 'Lines', 'order', 'score');
    end

    load(res_datafile);

    if run_word_map
        if run_alt_acc
            [map,valid_acc] = word_lookup_map(Clust, Comps, Syms, 'order', ...
               order,'restrict_order_to_class', true, ...
               'calc_valid_acc', true, 'break_ties_via_density', true);
            t = [t; sum(valid_acc(:,2)) / sum(valid_acc(:,1))];
            cc = char(Clust.truth_label);
            l_idx = find(cc >= 97 & cc <= 122);
            u_idx = find(cc >= 65 & cc <= 90);
            d_idx = find(cc >= 48 & cc <= 57);
            o_idx = find((cc >= 58 & cc <= 64) | (cc >= 91 & cc <= 96));
            s_idx = find(cc == 10 | cc == 32);
            l = [l; sum(valid_acc(l_idx,2)) / sum(valid_acc(l_idx,1))];
            u = [u; sum(valid_acc(u_idx,2)) / sum(valid_acc(u_idx,1))];
            d = [d; sum(valid_acc(d_idx,2)) / sum(valid_acc(d_idx,1))];
            o = [o; sum(valid_acc(o_idx,2)) / sum(valid_acc(o_idx,1))];
            s = [s; sum(valid_acc(s_idx,2)) / sum(valid_acc(s_idx,1))];
        else
            %map = word_lookup_map(Clust, Comps, Syms, 'order', order, ...
            %      'restrict_order_to_class', true, 'calc_valid_acc', false);
            %@@
            map = cell2mat(order);
            map = map(:,1);
            %@@
        end
        fprintf('word lookup mapping complete: %f\n', toc);
        save(res_datafile, 'Clust', 'Comps', 'Lines', 'order', 'score', ...
             'map');
    end
    
    load(res_datafile);

    %print out mapped ground truth to a text file, and determine accuracy stats
    if run_ocr_analysis
        pgs = Comps.files;
        for jj=1:length(pgs)
            lines = find(Lines.pg == jj);
            txt_file = imgs{idx(jj)};
            res_txtfile = [res_dir, '/', txt_file];
            res_char_rprtfile = [res_txtfile, '.char_rprt'];
            res_word_rprtfile = [res_txtfile, '.word_rprt'];
            print_ocr_text(lines, Comps, Syms, map, ...
                   'display_text', false, 'save_results', true, ...
                   'save_file', res_txtfile);
            cmd = ['accuracy ', pg_dir, txt_file, ' ', ...
                   res_txtfile, ' ', res_char_rprtfile];
            s = unix(cmd);
            if s ~= 0
                error('prob running accuracy. cmd: %s', cmd);
            end
            cmd = ['wordacc ', pg_dir, txt_file, ' ', ...
                   res_txtfile, ' ', res_word_rprtfile];
            s = unix(cmd);
            if s ~= 0
                error('prob running word accuracy. cmd: %s', cmd);
            end
        end
        %combine all the report files in this directory into a single
        %cumulative report
        char_rprts = dir([res_dir, '/*.char_rprt']);
        word_rprts = dir([res_dir, '/*.word_rprt']);
        char_rprt_list = '';
        word_rprt_list = '';
        if length(char_rprts) > 1
            for jj=1:length(char_rprts)
                char_rprt_list = [char_rprt_list, res_dir, '/', ...
                                  char_rprts(jj).name, ' '];
                word_rprt_list = [word_rprt_list, res_dir, '/', ...
                                  word_rprts(jj).name, ' '];
            end
            cmd = ['accsum ', char_rprt_list, ' > ', res_dir, '/', ...
                   docs{ii}, '.chartot_rprt'];
            s = unix(cmd);
            if s ~= 0
                error('prob running accsum. cmd: %s', cmd);
            end
            cmd = ['wordaccsum ', word_rprt_list, ' > ', res_dir, '/', ...
                   docs{ii}, '.wordtot_rprt'];
            s = unix(cmd);
            if s ~= 0
                error('prob running wordaccsum. cmd: %s', cmd);
            end
        else
            %just copy the single file for the total count
            cmd = ['cp ', res_dir, '/', char_rprts(1).name, ' ', res_dir, ...
                   '/', docs{ii}, '.chartot_rprt'];
            s = unix(cmd);
            if s ~= 0
                error('prob running cp. cmd: %s', cmd);
            end
            cmd = ['cp ', res_dir, '/', word_rprts(1).name, ' ', res_dir, ...
                   '/', docs{ii}, '.wordtot_rprt'];
            s = unix(cmd);
            if s ~= 0
                error('prob running cp. cmd: %s', cmd);
            end
        end

        fprintf('ocr analysis complete: %f\n', toc);
    end
end

if run_alt_acc
    fprintf('\n\n ALTERNATE ACCURACY STATISTICS\n\n');
    fprintf('overall average: %.4f (min %.4f, median %.4f, max %.4f)\n', ...
            mean(t), min(t), median(t), max(t));
    fprintf('lowercase average: %.4f (min %.4f, median %.4f, max %.4f)\n', ...
            mean(l), min(l), median(l), max(l));
    fprintf('uppercase average: %.4f (min %.4f, median %.4f, max %.4f)\n', ...
            mean(u), min(u), median(u), max(u));
    fprintf('digit average: %.4f (min %.4f, median %.4f, max %.4f)\n', ...
            mean(d), min(d), median(d), max(d));
    fprintf('othersym average: %.4f (min %.4f, median %.4f, max %.4f)\n', ...
            mean(o), min(o), median(o), max(o));
    keyboard
end

if create_diary
    fprintf('EXPERIMENT ENDED: %s\n', datestr(now));
    diary off;
end
