function Syms = create_alphabet(file, varargin)
% CREATE_ALPHABET   Initialize a struct containing output alphabet symbols
%
%   SYMS = CREATE_ALPHABET(FILE, ['var1', new_val1]...)
%   FILE should be a string listing the path and name of the file containing
%   the alphabet of output symbols to choose amongst during character 
%   recognition.  We assume the file is encoded in the default Locale (though
%   this should be able to be overridden)
%
%   SYMS is a struct meant to hold information on each output symbol.
%   It contains the following fields:
%     num - integer specifying the largest symbol index number.
%     input_file - this specifies the path and name of the file used to find
%                  the symbols
%     encoding - character encoding used for the symbols
%     val - this vector will hold integer representations of each encoded
%           symbol.  Since these will be displayed using the char() function,
%           the encoding on the machine being run must match the encoding of
%           the symbols for them to be displayed correctly elsewhere in the code
%     img - this is optionally created (depending on parameter settings below),
%           and will store a template image representation of the symbol.  The
%           size and font used are defined below.  If present this is used to
%           initially guide initial mappings between cluster images and
%           symbols.
%     corpus_files - this is optionally created as a cell array, and used to
%                    store the list of text files read to determine bigram
%                    counts and words etc.
%     NOTE: we assume the symbol alphabet is a superset of the symbols found in
%           the corpora
%     count - a vector of values listing how many times each symbol value
%             appears in the corpus.
%     bigram - A distribution over which symbols are likely to follow other
%              symbols based on counts in the corpora (stored as a matrix).
%              The entries are (possibly smoothed) counts listing how many
%              times one character was seen following another.
%     first_count - a vector values listing how many times each symbol value
%                   appears at the start of a line (possibly smoothed)
%     words - a cell array of all the words grouped together from symbols in
%             the alphabet, and found in the corpora
%     word_count - a vector listing how many times each word appears in the
%                  corpora


% CVS INFO %
%%%%%%%%%%%%
% $Id: create_alphabet.m,v 1.1 2006-10-29 17:06:21 scottl Exp $
%
% REVISION HISTORY
% $Log: create_alphabet.m,v $
% Revision 1.1  2006-10-29 17:06:21  scottl
% initial revision
%


% LOCAL VARS %
%%%%%%%%%%%%%%

%set default encoding to this machines locale
encoding = feature('DefaultCharacterSet');  

%by default we don't generate templates.  Change this to a string giving the 
%fontname (or full path to a pk font) to generate templats.
template_font = []; 

%in what point size should the templates be generated.  This has no effect if
%templates are not being generated, or if we are using a pk file in a
%particular DPI
font_ptsize = 32;

%how can we tell if a template font passed is the path to a pk font?
pk_pattern = 'pk$';  %match *pk

%by default we don't process any corpora looking for word and character counts
corpora_files = {};

%if processing corpora, how many pseudocounts should we add to each bigram
%entry?
bg_pseudo = 1;

%if processing corpora, how many pseudocounts should we add to each first
%character in line appearance?
fc_pseudo = 1;


% CODE START %
%%%%%%%%%%%%%%
tic;

%process arguments
if nargin < 1
    error('must specify a file to process!');
elseif nargin > 1
    process_optional_args(varargin{:});
end

%first ensure the file passed exists and can be opened for reading
fid = fopen(file, 'r', 'n', encoding);

if fid == -1
    error('problems opening the symbol file passed\n');
end

Syms = init_symbols(file, encoding);

%read all characters (including whitespace, but ignoring the trailing newline)
char_list = fgetl(fid)';
fclose(fid);

Syms.val = double(char_list);
Syms.num = length(Syms.val);

if ~isempty(template_font)
    fprintf('%.2fs: generating template images\n');

    if isempty(regexp(template_font, pk_pattern))
        Syms.img = generate_templates(template_font, char_list, ...
                   'ptsize', font_ptsize);
    else
        %check the pk file exists (can be opened)
        Syms.img = generate_pk_templates(template_font, char_list);
    end
end

if ~isempty(corpora_files)
    fprintf('%.2fs: reading text corpus\n');
    D = create_word_dictionary(corpora_files);

    if length(D.char) > Syms.num
        error('more symbols in corpus than in specified symbol files');
    end
    Syms.count = zeros(Syms.num, 1, 'uint32');
    Syms.bigram = zeros(Syms.num, Syms.num);
    Syms.first_count = zeros(Syms.num, 1, 'uint32');

    %must find the mapping between characters found in the corpus, and our
    %symbol characters
    idx = zeros(length(D.char),1);
    for ii=1:length(D.char)
        pos = strfind(char_list', D.char(ii));
        if length(pos) ~= 1
            error('symbol: "%c" in corpus, is not in symbol list', D.char(ii));
        end
        idx(ii) = pos;
    end
    Syms.count(idx) = D.char_count;

    %smooth the bigram by adding pseudo-counts
    Syms.bigram(idx,idx) = D.char_bigram;
    Syms.bigram = Syms.bigram + bg_pseudo;

    %smooth the start counts by adding pseudo-counts
    Syms.first_count(idx) = D.first_count;
    Syms.first_count = Syms.first_count + fc_pseudo;

    Syms.corpus_files = corpora_files;
    Syms.words = D.word;
    Syms.word_count = D.word_count;
end


fprintf('%.2fs: Symbols initialized\n');


% SUBFUNCTION DECLARATIONS %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%this function creates an empty symbol stucture
function Syms = init_symbols(file, enc)

Syms.num = uint16(0);
Syms.input_file = file;
Syms.encoding = enc;
Syms.val = double([]);  %easiest to convert from double
Syms.img = cell(0);
Syms.corpus_files = cell(0);
Syms.count = uint32([]);
Syms.bigram = [];
Syms.first_count = uint32([]);
Syms.words = cell(0);
Syms.word_count = uint32([]);