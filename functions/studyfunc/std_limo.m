% std_limo() - Export and run in LIMO the EEGLAB STUDY design.
%           call limo_batch to create all 1st level LIMO_EEG analysis + RFX
%
% Usage:
%   [STUDY LIMO_files] = std_limo(STUDY,ALLEEG,'key',val) 
%
% Inputs:
%  STUDY        - studyset structure containing some or all files in ALLEEG
%  ALLEEG       - vector of loaded EEG datasets
%
% Optional inputs:
%  'measure' - ['daterp'|'icaerp'|'datspec'|'icaspec'|'datersp'|'icaersp']
%              measure to compute. Currently, only 'daterp' and
%             'datspec' are supported. Default is 'daterp'.
%  'method'  - ['OLS'|'WTS'] Ordinary Least Square (OLS) or Weighted Least
%              Square (WTS). WTS should be used as it is more robust. It is
%              slower though.
%  'design'  - [integer] design index to process. Default is the current
%              design stored in STUDY.currentdesign.
%  'erase'   - ['on'|'off'] erase previous files. Default is 'on'.
%  'neighboropt' - [cell] cell array of options for the function computing
%              the channel neighbox matrix std_prepare_chanlocs(). The file
%              is saved automatically if channel location are present.
%              This option allows to overwrite the defaults when computing
%              the channel neighbox matrix.
%      
% Outputs:
%  STUDY     - modified STUDY structure (the STUDY.design now contains a list
%              of the limo files) 
%  LIMO_files a structure with the following fields
%     LIMO_files.LIMO the LIMO folder name where the study is analyzed
%     LIMO_files.mat a list of 1st level LIMO.mat (with path)
%     LIMO_files.Beta a list of 1st level Betas.mat (with path)
%     LIMO_files.con a list of 1st level con.mat (with path)
%     LIMO_files.expected_chanlocs expected channel location neighbor file for
%                                  correcting for multiple comparisons
% Example:
%  [STUDY LIMO_files] = std_limo(STUDY,ALLEEG,'measure','daterp') 
%
% Author: Cyril Pernet (LIMO Team), The university of Edinburgh, 2014
%         Ramon Martinez-Cancino and Arnaud Delorme, SCCN, 2014
%
% Copyright (C) 2015  Ramon Martinez-Cancino,INC, SCCN
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

function [STUDY, LIMO_files] = std_limo(STUDY,ALLEEG,varargin)

if nargin < 2
    help std_limo;
    return;
end;

if isstr(varargin{1}) && ( strcmpi(varargin{1}, 'daterp') || strcmpi(varargin{1}, 'datspec'))
    opt.measure  = varargin{1};
    opt.design   = varargin{2};
    opt.erase    = 'on';
    opt.method   = 'OSL';
else
    opt = finputcheck( varargin, ...
        { 'measure'        'string'  { 'daterp' 'datspec' } 'daterp'; ...
          'method'         'string'  { 'OLS' 'WLS'        } 'OLS';
          'design'         'integer' [] STUDY.currentdesign;
          'erase'          'string'  { 'on','off' }   'off';
          'splitreg'       'string'  { 'on','off' }   'off';
          'neighboropt'    'cell'    {}               {} }, ...
          'std_limo');
    if isstr(opt), error(opt); end;
end;
Analysis     = opt.measure;
design_index = opt.design;

% computing channel neighbox matrix
% ---------------------------------
if isfield(ALLEEG(1).chanlocs, 'theta')
    if  ~isfield(STUDY.etc,'statistic')
        STUDY = pop_statparams(STUDY, 'default');
    end
    [tmp1 tmp2 limostruct] = std_prepare_neighbors(STUDY, ALLEEG, 'force', 'on', opt.neighboropt{:});
    limoChanlocs = fullfile(STUDY.filepath, 'limo_chanlocs_pval_correct.mat');
    save('-mat', limoChanlocs, '-struct', 'limostruct');
    fprintf('Saving channel neighbors for correction for multiple comparisons in %s\n', limoChanlocs);
else
    disp('Warning: cannot compute expected channel distance for correction for multiple comparisons');
    limoChanlocs = [];
end;

% 1st level analysis
% -------------------------------------------------------------------------
model.cat_files = [];
model.cont_files = [];
if isempty(STUDY.design(design_index).filepath)
    STUDY.design(design_index).filepath = STUDY.filepath;
end
unique_subjects = unique({STUDY.datasetinfo.subject});
nb_subjects   = length(unique_subjects);

for s = 1:nb_subjects
    nb_sets(s) = numel(find(strcmp(unique_subjects{s},{STUDY.datasetinfo.subject})));
end

% Checking that all subjects use the same sets (should not happen)
% -------------------------------------------------------------------------
if length(unique(nb_sets)) ~= 1
   error('different numbers of datasets (.set) used across subjects - cannot go further')
else
   nb_sets = unique(nb_sets);
end

% simply reshape to read columns
% -------------------------------------------------------------------------
for s = 1:nb_subjects
    order{s} = find(strcmp(unique_subjects{s},{STUDY.datasetinfo.subject}));
end

% Detecting type of analysis
% -------------------------------------------------------------------------
if strncmp(Analysis,'dat',3)
    model.defaults.type = 'Channels';
elseif strncmp(Analysis,'ica',3)
    [STUDY,flags]=std_checkdatasession(STUDY,ALLEEG);
    if sum(flags)>0
        error('some subjects have data from different sessions - can''t do ICA');
    end
    model.defaults.type = 'Components';
    model.defaults.icaclustering = 1;
end

% Cleaning old files from the current design (Cleaning ALL)
% -------------------------------------------------------------------------
% NOTE: Clean up the .lock files to (to be implemented)
if strcmp(opt.erase,'on')
    [tmp,filename] = fileparts(STUDY.filename);
    
    % Cleaning level 1 folders
    for i = 1:nb_subjects
        tmpfiles = dir([STUDY.filepath filesep 'LIMO_' filename filesep unique_subjects{i} filesep 'GLM' num2str(STUDY.currentdesign) '*']);
        tmpfiles = {tmpfiles.name};
        if ~isempty(tmpfiles)
            for j = 1:length(tmpfiles)
                rmdir([STUDY.filepath filesep 'LIMO_' filename filesep unique_subjects{i} filesep tmpfiles{j}],'s');
            end
        end
    end
    
   
    
    % Cleaning level 2 folders
    if isfield(STUDY.design(design_index),'limo') && isfield(STUDY.design(design_index).limo,'groupmodel')
        for nlimos = 1:length(STUDY.design(design_index).limo)
            for ngroupmodel = 1:size(STUDY.design(design_index).limo(nlimos).groupmodel,2)
                    path2file = fileparts(STUDY.design(design_index).limo(nlimos).groupmodel(ngroupmodel).filename);
                    try
                        rmdir(path2file,'s');
                    catch
                        fprintf(2,['Fail to remove. Folder ' path2file ' does not exist or has been removed\n']);
                    end
            end
            
        end
    end
    
    % Cleaning files related with design (innecesary??)
    tmpfiles = dir([STUDY.filepath filesep 'LIMO_' filename]);
    tmpfiles = {tmpfiles.name};
    
    filecell = strfind(tmpfiles,['GLM' num2str(STUDY.currentdesign)]);
    indxtmp = find(not(cellfun('isempty',filecell)));
    if ~isempty(indxtmp)
        for nfile = 1:length(indxtmp)
            try
                file2delete = [STUDY.filepath filesep 'LIMO_' filename filesep tmpfiles{indxtmp(nfile)}];
                if isdir(file2delete)
                    rmdir(file2delete,'s');
                else
                    delete(file2delete);
                end
            catch
                fprintf(2,['Fail to remove. File ' tmpfiles{indxtmp(nfile)} ' does not exist or has been removed\n']);
            end
        end
    end
    
    % Cleaning limo fields
    STUDY.design(STUDY.currentdesign).limo = [];
    
end

% Check if the measures has been computed
% -------------------------------------------------------------------------
for nsubj = 1 : length(unique_subjects)
    inds     = find(strcmp(unique_subjects{nsubj},{STUDY.datasetinfo.subject}));
    subjpath = fullfile(STUDY.datasetinfo(inds(1)).filepath, [unique_subjects{nsubj} '.' lower(Analysis)]);  % Check issue when relative path (remove comment)
    if exist(subjpath,'file') ~= 2
        error('std_limo: Measures must be computed first');
    end
end
 
measureflags = struct('daterp','off',...
                     'datspec','off',...
                     'datersp','off',...
                     'datitc' ,'off',...
                     'icaerp' ,'off',...
                     'icaspec','off',...
                     'icaersp','off',...
                     'icaitc','off');
                 
measureflags.(lower(Analysis))= 'on';
STUDY.etc.measureflags = measureflags;

% Checking if continuous variables
% -------------------------------------------------------------------------
if isfield(STUDY.design(design_index).variable,'vartype')
    if any(strcmp(unique({STUDY.design(design_index).variable.vartype}),'continuous'))
        cont_var_flag = 1;
    else
        cont_var_flag = 0;
    end
else
    error('std_limo: Define a valid design');
end
% -------------------------------------------------------------------------
for s = 1:nb_subjects     
    % model.set_files: a cell array of EEG.set (full path) for the different subjects
    if nb_sets == 1
        index = STUDY.datasetinfo(order{s}).index;
        names{s} = STUDY.datasetinfo(order{s}).subject;
        
        % Creating fields for limo
        % ------------------------
        ALLEEG(index) = std_lm_seteegfields(STUDY,order{s},'datatype',model.defaults.type,'format', 'cell');
        
        model.set_files{s} = fullfile(ALLEEG(index).filepath,ALLEEG(index).filename);
        
    else
        index = [STUDY.datasetinfo(order{s}).index];
        tmp   = {STUDY.datasetinfo(order{s}).subject};
        if length(unique(tmp)) ~= 1
            error('it seems that sets of different subjects are merged')
        else
            names{s} =  cell2mat(unique(tmp));
        end
        
        % Creating fields for limo
        % ------------------------
        for sets = 1:length(index)
            EEGTMP = std_lm_seteegfields(STUDY,index(sets),'datatype',model.defaults.type,'format', 'cell');
            ALLEEG = eeg_store(ALLEEG, EEGTMP, index(sets));
        end
 
        model.set_files{s} = [ALLEEG(index(1)).filepath filesep 'merged_datasets_design' num2str(design_index) '.set'];
        
        OUTEEG = pop_mergeset(ALLEEG,index,1);
        OUTEEG.filename = ['merged_datasets_design' num2str(design_index) '.set'];
        OUTEEG.datfile = [];
        
        % update EEG.etc
        OUTEEG.etc.merged{1} = ALLEEG(index(1)).filename;
        
        % Def fields
        OUTEEG.etc.datafiles.daterp   = [];
        OUTEEG.etc.datafiles.datspec  = [];
        OUTEEG.etc.datafiles.dattimef = [];
        OUTEEG.etc.datafiles.datitc   = [];
        OUTEEG.etc.datafiles.icaerp   = [];
        OUTEEG.etc.datafiles.icaspec  = [];
        OUTEEG.etc.datafiles.icatimef = [];
        OUTEEG.etc.datafiles.icaitc   = [];
        
        % Filling fields
        if isfield(ALLEEG(index(1)).etc.datafiles,'daterp')
            OUTEEG.etc.datafiles.daterp{1} = ALLEEG(index(1)).etc.datafiles.daterp;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'datspec')
            OUTEEG.etc.datafiles.datspec{1} = ALLEEG(index(1)).etc.datafiles.datspec;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'dattimef')
            OUTEEG.etc.datafiles.datersp{1} = ALLEEG(index(1)).etc.datafiles.dattimef;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'datitc')
            OUTEEG.etc.datafiles.datitc{1} = ALLEEG(index(1)).etc.datafiles.datitc;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'icaerp')
            OUTEEG.etc.datafiles.icaerp{1} = ALLEEG(index(1)).etc.datafiles.icaerp;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'icaspec')
            OUTEEG.etc.datafiles.icaspec{1} = ALLEEG(index(1)).etc.datafiles.icaspec;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'icatimef')
            OUTEEG.etc.datafiles.icaersp{1} = ALLEEG(index(1)).etc.datafiles.icatimef;
        end
        if isfield(ALLEEG(index(1)).etc.datafiles,'icaitc')
            OUTEEG.etc.datafiles.icaitc{1} = ALLEEG(index(1)).etc.datafiles.icaitc;
        end
        
        % Save info
        pop_saveset(OUTEEG, 'filename', OUTEEG.filename, 'filepath',OUTEEG.filepath,'savemode' ,'twofiles');
        clear OUTEEG
    end
    
    [catvar_matrix,tmp] = std_lm_getvars(STUDY,STUDY.datasetinfo(order{s}(1)).subject,'design',design_index,'vartype','cat'); clear tmp; %#ok<ASGLU>

    if ~isempty(catvar_matrix)
        if isvector(catvar_matrix) % only one factor of n conditions
            categ = catvar_matrix;
            model.cat_files{s} = catvar_matrix;
%         elseif 1
%             
%             trialinfo = std_combtrialinfo(STUDY.datasetinfo, order{s});
%             categ = std_builddesignmat(STUDY.design(design_index), trialinfo);
%             model.cat_files{s} = catvar_matrix;
%             
        else % multiple factors (=multiple columns)
            X = []; nb_row = size(catvar_matrix,1);
            for cond = 1:size(catvar_matrix,2)
                nb_col(cond) = max(unique(catvar_matrix(:,cond)));
                x = NaN(nb_row,nb_col(cond));
                for c=1:nb_col(cond)
                    x(:,c) = [catvar_matrix(:,cond) == c];
                end
                X = [X x];
            end
            
            tmpX = limo_make_interactions(X, nb_col);
            tmpX = tmpX(:,sum(nb_col)+1:end);
            getnan = find(isnan(catvar_matrix(:,1)));
            if ~isempty(getnan)
                tmpX(getnan,:) = NaN;
            end
            categ = sum(repmat([1:size(tmpX,2)],nb_row,1).*tmpX,2);
            clear x X tmpX; model.cat_files{s} = categ;
        end      
        save(fullfile(ALLEEG(index(1)).filepath, 'categorical_variable.txt'),'categ','-ascii')
    end
    
    % model.cont_files: a cell array of continuous variable files
    if cont_var_flag
        
        [contvar,contvar_info] = std_lm_getvars(STUDY,STUDY.datasetinfo(order{s}(1)).subject,'design',design_index,'vartype','cont'); clear tmp; %#ok<ASGLU>
        
        if nb_sets ~= 1;
%             [contvar_matrix,contvar_info] = std_lm_getvars(STUDY,STUDY.datasetinfo(order(1,s)).subject,'design',design_index,'vartype','cont');
            contvar_matrix = contvar; clear contvar;
            % we need to know the nb of trials in each of the sets
            set_positions = [0];
            getnan = find(isnan(contvar_matrix(:,1)));
            for dataset = 1:nb_sets
                cond_size = cellfun(@length,contvar_info.datasetinfo_trialindx(contvar_info.dataset == index(dataset)));
                set_size = sum(cond_size);
                set_positions(dataset+1) = set_size + sum(getnan<set_size);
                % update getnan as the next loop restart at one
                getnan((getnan - set_size)<0) = [];
            end
            set_positions = cumsum(set_positions);
            
            % create contvar updating with set_positions
            contvar = NaN(size(contvar_matrix));
            for cond = 1:size(contvar_info.datasetinfo_trialindx,2)
                which_dataset = contvar_info.dataset(cond);                    % dataset nb
                dataset_nb = find(which_dataset == order{s});                  % position in the concatenated data
                position = cell2mat(contvar_info.datasetinfo_trialindx(cond)); % position in the set
                values = contvar_matrix(position+set_positions(dataset_nb));   % covariable values
                contvar(position+set_positions(dataset_nb)) = values;          % position in the set + position in the concatenated data
            end
        end

        % --> split per condition and zscore (if requested)
        if exist('categ','var')
            if strcmp(opt.splitreg,'on')
                model.cont_files{s} = limo_split_continuous(categ,contvar);
            else
                model.cont_files{s} = contvar;
            end
        end
        
        if size(contvar,2) > 1
            save([ALLEEG(index(1)).filepath filesep 'continuous_variables.txt'],'categ','-ascii')
        else
            save([ALLEEG(index(1)).filepath filesep 'continuous_variable.txt'],'categ','-ascii')
        end
    end
end

model.set_files = model.set_files';
model.cat_files = model.cat_files';
if cont_var_flag
    model.cont_files = model.cont_files';
end

% set model.defaults - all conditions no bootstrap
% -----------------------------------------------------------------
% to update passing the timing/frequency from STUDY - when computing measures
% -----------------------------------------------------------------
if strcmp(Analysis,'daterp') || strcmp(Analysis,'icaerp')
    model.defaults.analysis= 'Time';
    model.defaults.start = ALLEEG(index(1)).xmin*1000; %-10; 
    model.defaults.end   = ALLEEG(index(1)).xmax*1000;
    model.defaults.lowf  = [];
    model.defaults.highf = [];
    
elseif strcmp(Analysis,'datspec') || strcmp(Analysis,'icaspec')
    
    model.defaults.analysis= 'Frequency';
    model.defaults.start   = -10;
    model.defaults.end     = ALLEEG(index(1)).xmax*1000;
    model.defaults.lowf    = [];
    model.defaults.highf   = [];
    
elseif strcmp(Analysis,'datersp') || strcmp(Analysis,'icaersp')
    model.defaults.analysis = 'Time-Frequency';
    model.defaults.start    = [];
    model.defaults.end      = [];
    model.defaults.lowf     = [];
    model.defaults.highf    = [];
end

model.defaults.fullfactorial = 0;                    % factorial only for single subject analyses - not included for studies
model.defaults.zscore = 0;                           % done that already
model.defaults.bootstrap = 0 ;                       % only for single subject analyses - not included for studies
model.defaults.tfce = 0;                             % only for single subject analyses - not included for studies
model.defaults.method = opt.method;                  % default is OLS - to be updated to 'WLS' once validated
model.defaults.Level= 1;                             % 1st level analysis
model.defaults.type_of_analysis = 'Mass-univariate'; % future version will allow other techniques

STUDY.design_info = STUDY.design(design_index).variable;
STUDY.design_index = design_index; % Limo batch have to be fixed to use the field STUDY.currentdesig
STUDY.names = names;

% contrast
if cont_var_flag && exist('categ','var')
    if strcmp(opt.splitreg,'on')
        limocontrast.mat = [zeros(1,max(categ)) ones(1,max(categ)) 0];
    else
        limocontrast.mat = [zeros(1,max(categ))  ones(1,size(contvar,2)) 0];
    end
    LIMO_files = limo_batch('both',model,limocontrast,STUDY);
else
    limocontrast.mat = [];
    LIMO_files = limo_batch('model specification',model,limocontrast,STUDY);
end
LIMO_files.expected_chanlocs = limoChanlocs;

for i = 1:length(LIMO_files.Beta)
    limofolders{i} = fileparts(LIMO_files.mat{i});
end

% Getting indices to save LIMO in STUDY structure (save multiples analysis)
% -------------------------------------------------------------------------
if isfield(STUDY.design(STUDY.currentdesign),'limo') && isfield(STUDY.design(STUDY.currentdesign).limo, 'datatype')
    stdlimo_indx = find(strcmp({STUDY.design(STUDY.currentdesign).limo.datatype},Analysis));
     if isempty(stdlimo_indx)
         stdlimo_indx = length(STUDY.design(STUDY.currentdesign).limo) + 1;
     end   
else
    stdlimo_indx = 1;
end

% Cleaning
% -------------------------------------------------------------------------
rmfield(STUDY,'design_index');
rmfield(STUDY,'design_info');
rmfield(STUDY,'names');

% Clenainig level 2 folders associated to specific analaysis if opt.erase =
% 'off' (IF EXIST BEFORE)
if strcmp(opt.erase,'off')
    if isfield(STUDY.design(STUDY.currentdesign),'limo') && length(STUDY.design(STUDY.currentdesign).limo) >= stdlimo_indx
        STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).model = [];
        STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).groupmodel = [];
    end
end

% Assigning info to STUDY
% -------------------------------------------------------------------------
STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).datatype = Analysis;
STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).chanloc  = LIMO_files.expected_chanlocs;

for i =1:size(LIMO_files.mat,1)
    STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).basefolder_level1{i}  = fileparts(LIMO_files.mat{i});
    tmp = dir(fileparts(LIMO_files.mat{i}));
    if ~isempty({tmp.name})
        outputfiles = {tmp.name}';
        
        % Cleaning out the list
        %----------------------
        cleanoutlist = {'Betas.mat','LIMO.mat','Yr.mat','Yhat.mat','Res.mat','.','..'};
        for j = 1:length(cleanoutlist)
            ind2delete{j} = find(strcmp(outputfiles,cleanoutlist{j}));
        end
        nonemptyvals              = find(cellfun(@(x) ~isempty(x), ind2delete));
        ind2delete                = [ind2delete{nonemptyvals}];
        outputfiles(ind2delete) = []; 
        clear ind2delete;
    end
    for nfiles = 1:size(outputfiles,1)
        STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).model(i).filename{nfiles,1}  = fullfile(fileparts(LIMO_files.mat{i}),outputfiles{nfiles}); 
        [trash,tmp] = fileparts(outputfiles{nfiles});
        STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).model(i).guiname{nfiles,1} = tmp;
    end
end

cd(STUDY.filepath);

% Computing Stats (Just ttest and paired ttest ... by now)
% -------------------------------------------------------------------------
% NOTE: 
% 1- Still need to consider the way to figure it out the types of contrast to perform
% 2- Group variables need to be defined to split data in groups. ??

% 1 - Computing ttest for each parameter
nparams = 0;
if exist('categ','var'),   nparams = max(categ); end;
if exist('contvar','var'), nparams = nparams + size(contvar,2); end;    

foldername = [STUDY.filename(1:end-6) '_GLM' num2str(STUDY.currentdesign) '_' model.defaults.type '_' model.defaults.analysis '_'];
nbootval   = 0;
tfceval    = 0;
folderpath = LIMO_files.LIMO;
chanloc    = STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).chanloc ;

filesout = limo_random_select(1,LIMO_files.expected_chanlocs,'nboot'         ,nbootval...
                                                            ,'tfce'          ,tfceval...
                                                            ,'analysis_type' ,'fullchan'...
                                                            ,'parameters'    ,{[1:nparams]}...
                                                            ,'limofiles'     ,{LIMO_files.Beta}...;
                                                            ,'folderprefix'  ,foldername...
                                                            ,'folderpath'    ,LIMO_files.LIMO);
testype    = cell([length(filesout),1]);
testype(:) = {'ttest'};
for i = 1: nparams
testname{i,1}   = [testype{i} '_parameter' num2str(i)];
end

% 2- Computing Paired ttest for each combination of parameters
ncomb        = combnk(1:nparams,2);
limofiles{1} = LIMO_files.Beta;  
limofiles{2} = LIMO_files.Beta; 

for i = 1:size(ncomb,1)
    tmpname          = [foldername 'par_' num2str(ncomb(i,1)) '_' num2str(ncomb(i,2))];
    mkdir(LIMO_files.LIMO,tmpname);
    folderpath       = fullfile(LIMO_files.LIMO,tmpname);
    filesout{end+1}  = limo_random_select(2,LIMO_files.expected_chanlocs,'nboot'         ,nbootval...
                                                     ,'tfce'          ,tfceval...
                                                     ,'analysis_type' ,'fullchan'...
                                                     ,'parameters'    ,{[ncomb(i,1)] [ncomb(i,2)]}...
                                                     ,'limofiles'     ,limofiles...
                                                     ,'folderpath'    ,folderpath);      
    testype{end+1}      = 'p_ttest';
    testname{end+1,1}   = [testype{end} '_parameter_' num2str(ncomb(i,1)) '-' num2str(ncomb(i,2))];
end
% Assigning Level 2 info to STUDY
% STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).l2files = [testype testname filesout' ];

 for i = 1:size(filesout,2)
     STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).groupmodel(i).filename = filesout{1,i};
     STUDY.design(STUDY.currentdesign).limo(stdlimo_indx).groupmodel(i).guiname  = testname{i,1};
 end

% Saving STUDY
STUDY = pop_savestudy( STUDY, [],'filepath', STUDY.filepath,'savemode','resave');