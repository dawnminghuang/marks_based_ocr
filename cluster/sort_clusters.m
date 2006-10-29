function [Clust, Comps] = sort_clusters(Clust, Comps)
% SORT_CLUSTERS   Sort (by descending number of elements) the Clusters passed
%
%   [Clust, Comps] = SORT_CLUSTERS(Clust, Comps)
%
%   Clust should be a struct with several fields including the number of 
%   components that belong to each cluster.
%
%   Comps should be a struct containing several fields including the cluster
%   id to which it belongs.  We need to pass in Comps since once it is sorted
%   these values will have to be changed.
%
%   The Clust array elements are returned in decreasing order
%   according to the number of components belonging to them, but are otherwise
%   unchanged.  Similarly Comps.clust is updated to reflect the new cluster 
%   numbering.
%

% CVS INFO %
%%%%%%%%%%%%
% $Id: sort_clusters.m,v 1.4 2006-10-29 17:24:54 scottl Exp $
%
% REVISION HISTORY
% $Log: sort_clusters.m,v $
% Revision 1.4  2006-10-29 17:24:54  scottl
% change to cluster struct, to use descender and ascender offsets, instead
% of a single offset field.
%
% Revision 1.3  2006/08/24 21:40:04  scottl
% added ability to use the mode instead of taking the average of cluster
% intensities while refining.
%
% Revision 1.2  2006/07/05 01:17:37  scottl
% rewritten based on new cluster and component structures.
%
% Revision 1.1  2006/06/03 20:55:48  scottl
% Initial check-in.
%


% LOCAL VARS %
%%%%%%%%%%%%%%


% CODE START %
%%%%%%%%%%%%%%
if nargin ~= 2
    error('incorrect number of arguments passed!');
end

[Dummy, idx] = sort([Clust.num_comps],1,'descend');
Clust.comps = Clust.comps(idx);
Clust.num_comps = Clust.num_comps(idx);
Clust.mode_num = Clust.mode_num(idx);
Clust.avg = Clust.avg(idx);
Clust.norm_sq = Clust.norm_sq(idx);
Clust.refined = Clust.refined(idx);
Clust.descender_off = Clust.descender_off(idx);
Clust.ascender_off = Clust.ascender_off(idx);
if ~isempty(Clust.bigram)
    Clust.bigram = Clust.bigram(idx,:);
end

%now we update the components associated cluster id
for ii = 1:Clust.num
    Comps.clust(Clust.comps{ii}) = ii;
end
