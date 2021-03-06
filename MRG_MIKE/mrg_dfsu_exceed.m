function [data] = mrg_dfsu_exceed(exceed, chunk_size)
% Performs an exceedance analysis on a DFSU files.
%
% INPUT
%   exceed          A vector representing the quantiles to extract.  
%                   Defualts to [.10 .20 .30 .50]
%   chunk_size      An integer specifying the size of the 'chunks' to break 
%                   the file up into.  Larger chunks may speed up runtime, 
%                   but very large chunks may lead to out of memory errors.  
%                   Defaults to 1000.
%
% OUTPUT
%   A MATLAB structure with n+3 items, where n is the number of 
%   quantiles requested, plus X, Y and Z data from the DFSU file.  
%   A CSV file, derived from the MATLAB structure.
%   A DFSU file with the same spatial extent as the analysed file, but 
%   with a single timestep will be written as 'inputfilename_exceed.dfsu'.
%
% REQUIREMENTS
%   The DHI/MIKE Matlab toolbox 2011 (developed with v. 20110304)
%   mrg_struct_to_csv.m function (assuming you want csv output, else it will be skipped)
%
% NOTES
% 	Extracts quantiles from each cell in a DFSU file (i.e. an analysis
%   through the time domain).
%
% LICENCE
%   Created by Daniel Pritchard (www.pritchard.co)
%   Distributed under a creative commons CC BY-SA licence. See here:
%   http://creativecommons.org/licenses/by-sa/3.0/
%
% DEVELOPMENT
%   v 1.0   6/7/2012
%           DP. Initial attempt and distribution. 
%   v 1.1   12/7/2012
%           DP. Added better filenaming and removed error-causing 'factory' call. 
%   v 1.2   19/7/2012
%           DP. Now deals with delete values by using single() throughout (use of
%           double() causes issues with rounding).
%           DP. Much better estimation of time remaining.
%   v 1.3   14/02/2013
%           DP. Documentation

%% Go!
% Exceedance values (a vector)
if ~exist('exceed', 'var')
    exceed = [.10 .20 .30 .50];
end

% Chunk size...
if ~exist('chunk_size', 'var')
    chunk_size = 1000;
end

% Load libraries
NET.addAssembly('DHI.Generic.MikeZero.DFS');
NET.addAssembly('DHI.Generic.MikeZero.EUM');
import DHI.Generic.MikeZero.DFS.*;
import DHI.Generic.MikeZero.DFS.dfsu.*;
import DHI.Generic.MikeZero.*

% Get file
[filename,filepath] = uigetfile('*.dfsu','Select the .dfsu file to analyse');
infile = [filepath,filename];
dfsu_file = DfsFileFactory.DfsuFileOpen(infile);

% Read some item information
items = {};
for i = 0:dfsu_file.ItemInfo.Count-1
    item = dfsu_file.ItemInfo.Item(i);
    items{i+1,1} = char(item.Name);
    items{i+1,2} = char(item.Quantity.Unit);
    items{i+1,3} = char(item.Quantity.UnitAbbreviation);
end

% Ask the user to select the item to process
choice = menu(sprintf('Which of these objects do you want to process?'),items{:,1}, 'Ummm... None of the above!');
if choice == 0 || choice == length(items(:,1))+1
    error('Do or do not.  There is no try.');
else
    dfsu_item = choice; % A number delimiting the item position in the DFSU file.  The same as mat_item (i.e. no zero indexing).  i.e. this is completly redundant!
end

nsteps = dfsu_file.NumberOfTimeSteps;
nelements = dfsu_file.NumberOfElements;

% Setup the output object
data = struct();

% Add some nicities, like X, Y, Z
node_x = single(dfsu_file.X);
node_y = single(dfsu_file.Y);
node_z = single(dfsu_file.Z);
ele_table = mzNetFromElmtArray(dfsu_file.ElementTable);
[ele_X,ele_Y,ele_Z] = mzCalcElmtCenterCoords(ele_table,node_x,node_y,node_z);
data.X = ele_X.';
data.Y = ele_Y.';
data.Z = ele_Z.';

% Add (empty) objects for the exceedance values
for a = 1:length(exceed)
    data.(['quant_',regexprep(num2str(exceed(a)),'\.','')]) = NaN(1,nelements, 'single');
end

% Pre-allocate some memory, and setup our sequence...
temp_single_ts = NaN(1,nelements, 'single');
temp_el_chunk = NaN(chunk_size,nsteps, 'single');
seq = int32([1:chunk_size:nelements]);
seq_len = size(seq,2);
seq(end+1) = int32(nelements);

% Single delete value
sDelete = single(1e-35);

% Timings are for debugging and display only...
timings = NaN(1,seq_len);

% loc = Keeping track of the loctaion in the data file where we are at
loc = 0;
% OK this is ugly, but I think I implimented this after 4 beers at about
% 10 pm sitting at a coffee table in a rented apartment in Denmark.  If you
% wanted professional code you wouldn't rely on drunk, tired, algal
% physiologists!

for j=1:seq_len
    tic
    if j == seq_len
        %This is the last chunk.  Act accordingly.
        last_chunk_size = seq(j+1)-seq(j)+1;
        temp_el_chunk = ones(last_chunk_size,nsteps);
        for i=0:nsteps-1
            temp_single_ts(:) = single(dfsu_file.ReadItemTimeStep(dfsu_item,i).Data)';
            temp_el_chunk(:,i+1) = temp_single_ts(seq(j):seq(j+1));
        end
        % OK now we have a chunk.  We need to process it...
        nel_in_chunk = size(temp_el_chunk,1);
        disp(['Processing elements ', num2str(loc+1), ' to ' num2str(size(temp_el_chunk,1)+loc), ' of ', num2str(nelements)])
        
        % Convert delete values to NANs
        temp_el_chunk(temp_el_chunk==sDelete) = NaN;
        
        % Do the heavy lifting
        quant = quantile(temp_el_chunk,exceed,2);

        for a = 1:size(quant,2)
            data.(['quant_',regexprep(num2str(exceed(a)),'\.','')])(loc+1:size(temp_el_chunk,1)+loc) = quant(:,a);
        end
        loc = size(temp_el_chunk,1)+loc;
    else
        for i=0:nsteps-1
            temp_single_ts(:) = single(dfsu_file.ReadItemTimeStep(dfsu_item,i).Data)';
            temp_el_chunk(:,i+1) = temp_single_ts(seq(j):seq(j+1)-1);
        end
        % OK now we have a chunk.  We need to process it...
        nel_in_chunk = size(temp_el_chunk,1);
        %disp(['Processing element ', num2str(j), ' of ', num2str(nelements), ' in chunk ', num2str(j), ' of ', num2str(seq_len), '.'])
        disp(['Processing elements ', num2str(loc+1), ' to ' num2str(size(temp_el_chunk,1)+loc), ' of ', num2str(nelements)])
        
        % Convert delete values to NANs
        temp_el_chunk(temp_el_chunk==sDelete) = NaN;
        
        quant = quantile(temp_el_chunk,exceed,2);
        for a = 1:size(quant,2)
            data.(['quant_',regexprep(num2str(exceed(a)),'\.','')])(loc+1:size(temp_el_chunk,1)+loc) = quant(:,a);
        end
        loc = size(temp_el_chunk,1)+loc;
    end
    timings(j) = toc;
    mean_time_sec = nanmean(timings);
    remain = (seq_len-j)*mean_time_sec/60;
    disp(['Approximatly ', num2str(remain), ' minutes remain.'])
end

%% Here we write out a CSV file
if exist('mrg_struct_to_csv.m', 'file') == 2
    disp('Writing exceedance values to a CSV file.')
    out_file = [filename(1:end-5),'_',regexprep(items{choice,1},' ',''),'_exceed.csv'];
    out_file_full = [filepath,out_file];
    mrg_struct_to_csv(data, out_file_full);
    disp(['Output CSV file (', out_file, ') written successfully.'])
else
    disp('mrg_struct_to_csv.m not avilable in your search path.  No CSV file will be generated.')
end

%% Here we  stick data into a DFSU file
% First DRAFT of the DFSU - based output...  Seems to work OK...
disp('Writing exceedance values to a DFSU file.')

% Apparently we need to load these again...  Hmmm... TODO: Figure this out
NET.addAssembly('DHI.Generic.MikeZero.DFS');
NET.addAssembly('DHI.Generic.MikeZero.EUM');
import DHI.Generic.MikeZero.DFS.*;
import DHI.Generic.MikeZero.DFS.dfsu.*;
import DHI.Generic.MikeZero.*
import DHI.Generic.MikeZero.EUM.*

builder = DfsuBuilder.Create(DfsuFileType.Dfsu2D);
builder.SetTimeInfo(dfsu_file.StartDateTime, 1);
builder.SetNodes(dfsu_file.X,dfsu_file.Y,dfsu_file.Z,dfsu_file.Code);
builder.SetElements(dfsu_file.ElementTable);
builder.SetProjection(dfsu_file.Projection);

data_names = fieldnames(data);

% Being lazy here - no need to write out X, Y and Z - TODO: Remove this...
for n = 1:length(data_names)
    builder.AddDynamicItem(data_names{n},eumQuantity(eumItem.eumIItemUndefined,eumUnit.eumUUnitUndefined));
end

out_file = [filename(1:end-5),'_',regexprep(items{choice,1},' ',''),'_exceed', filename(end-4:end)];
out_file_full = [filepath,out_file];

dfs_out = builder.CreateFile(out_file_full);

if ~(size(data.(data_names{1}), 2) == dfs_out.NumberOfElements)
    error(['Somehow there is a mismatch in the number of elements in the ',...
        'DFSU output file and the length of the data.  This is an error'])
end

% Follow up from above - Re: Layzness
for n = 1:length(data_names)
    data_out = single(data.(data_names{n}));
    data_out(isnan(data_out)) = sDelete;
    dfs_out.WriteItemTimeStepNext(n-1, NET.convertArray(data_out));
end

dfs_out.Close()
disp(['Output DFSU file (', out_file, ') written successfully.'])

end




