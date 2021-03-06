## flow table
options(scipen=999)
arg=commandArgs(T)
library(rgrass7)
library(rgdal)
gis = gmeta()

DtoR = pi/180
RtoD = 1/DtoR

projectFolder = arg[1]
# bounded by GIS mask
	basinMap = 'basin'
	hillslopeMap = 'hill'
	zoneMAP = 'patch'
	xMap = 'xmap'
	yMap = 'ymap'
	patchMAP = 'patch'
	rowMap = 'rowmap' ##<<--- raster calculator row()
	colMap = 'colmap' ##<<--- raster calculator col()
	demMap = 'dem'
	roadMap = 'roads'
	streamMap = 'str'
	slopeMap = 'slope' ## unit in degree
	drainMap = 'drain'

	rast0 = readRAST(c(basinMap, hillslopeMap, zoneMAP, patchMAP, rowMap, colMap),NODATA=0)
		mask = !is.na(rast0@data[[1]])
		basin = rast0@data[[1]][mask]
		hill = rast0@data[[2]][mask]
		zone = rast0@data[[3]][mask]
		patch = rast0@data[[4]][mask]
		rows = rast0@data[[5]][mask]
		cols = rast0@data[[6]][mask]
	rast1 = readRAST(c(demMap, xMap, yMap, slopeMap))
		dem = rast1@data[[1]][mask]
		xx = rast1@data[[2]][mask]
		yy = rast1@data[[3]][mask]
		slope = rast1@data[[4]][mask]
		
	rast2 = readRAST(streamMap)	
		stream = rast2@data[[1]][mask]
	
	rast3 = readRAST(roadMap)		
		road = rast3@data[[1]][mask]
	
	rast4 = readRAST(drainMap)		
		drain = abs(rast4@data[[1]][mask])
		
	## assume grids are squares 
	cellarea = gis$nsres * gis$ewres
	cellsize = sqrt(cellarea) 
	flatDEMdrop = tan(DtoR*0.143)*cellsize # only 0.25m drop per 100m.
	roadWidth = 5
	roadWidth = ifelse(cellsize>=9.99,
		5, # meters (default)
		ifelse(roadWidth>cellsize, cellsize, roadWidth)
	 )# ifelse
	directEdge = cellsize*0.5
	diagonalEdge = cellsize*sqrt(0.5)		
		
	# 1.  2. 3.  4. 5.  6. 7.  8. (GRASS from current drainTO code order)
	# NE, N, NW, W, SW, S, SE, E
	colneighbor = c(1,	0,	-1,	-1,	-1,	0,	1,	1)	
	rowneighbor = c(-1,	-1,	-1,	0,	1,	1,	1,	0)	
	directEdgeIndex = c(2,4,6,8)
	indirectEdgeIndex = c(1,3,5,7)
	 
	maxCol = max(cols,na.rm=T) 
	maskRC = rows*maxCol+cols #paste(rows, cols,sep=':') ## row*[max col]+col (yes: unique ID)
	gridSurroundRC = sapply(rows, FUN=function(x){x+rowneighbor})*maxCol+sapply(cols, FUN=function(x){x+colneighbor})
	
	
	# part 1: gathering information to temporary files
	#patch_title = c('patchID','dem','xx','yy','basin','hill','zone','rr','cc','grid','strQ','roadQ','accgrid','mslope','Mslope')

	fullLength = seq(1,length.out=length(patch))
	patch_info_dem = tapply(dem,INDEX=patch,mean)
	orderedPatch = as.numeric(names(patch_info_dem[order(patch_info_dem,decreasing=T)]))
	outputOrder = match(patch, orderedPatch)
	
	patchInfo = tapply(fullLength, INDEX=outputOrder, FUN=function(ii){
		
		return <- c(
			mean(patch[ii]), 			#1
			mean(dem[ii]),				#2
			mean(xx[ii]),				#3
			mean(yy[ii]),				#4
			mean(basin[ii]),			#5
			mean(hill[ii]),				#6
			mean(zone[ii]),				#7
			mean(rows[ii]),				#8
			mean(cols[ii]),				#9
			length(ii),					#10
			sum(!is.na(stream[ii])),	#11 strQ
			sum(!is.na(road[ii])),		#12 roadQ
			length(ii),					#13
			tan(mean(slope[ii])*DtoR),	#14
			tan(max(slope[ii])*DtoR)	#15
			);
	})#tapply <--- this output is a list of c()
	patch_info_lowest = patchInfo[[ length(patchInfo) ]]
	
	
	## part 2: sort by 'elevation' & finding neighbor 
	flow_table_buff = paste(length(patchInfo))
	silent = tapply(fullLength, INDEX=outputOrder, FUN=function(ii){
		# exmaple: patch 1629802; ii = fullLength[patch== 1629802]
		# exmaple: patch 3937; ii = fullLength[patch== 3937]
		
		currentPatchID = patch[ii][1]
		withinPatchGridRC = rows[ii]*maxCol+cols[ii] # within
		drainTO_index = cbind(drain[ii],ii)
		
		hold = as.vector(gridSurroundRC[directEdgeIndex,ii]) 
		withinNeighbour_DirectEdgeRC_edge = table( hold[!(hold%in% withinPatchGridRC) & hold%in%maskRC] ) * directEdge;
		withinNeighbour_DirectEdgeRC = as.numeric(names(withinNeighbour_DirectEdgeRC_edge))
		
		hold = as.vector(gridSurroundRC[indirectEdgeIndex,ii])
		withinNeighbour_IndirectEdgeRC_edge = table( hold[!(hold%in% withinPatchGridRC) & hold%in%maskRC] ) * diagonalEdge;
		withinNeighbour_IndirectEdgeRC = as.numeric(names(withinNeighbour_IndirectEdgeRC_edge))
		
		withinNeighbourRC_edge = c(withinNeighbour_DirectEdgeRC_edge, withinNeighbour_IndirectEdgeRC_edge) 	##<<------
		withinNeighbourRC = c(withinNeighbour_DirectEdgeRC, withinNeighbour_IndirectEdgeRC)					##<<------
		withinNeighbourRC_prefer = rep(0,length(withinNeighbourRC))											##<<------
		
			hold = as.vector(gridSurroundRC[ drainTO_index ])
			withinPatchGridRC_drainTO_RC_count = table( hold[!(hold%in% withinPatchGridRC) & hold%in%maskRC] )
			withinPatchGridRC_drainTO_RC = as.numeric(names(withinPatchGridRC_drainTO_RC_count))
			withinNeighbourRC_prefer[ match(withinPatchGridRC_drainTO_RC, withinNeighbourRC) ] = withinPatchGridRC_drainTO_RC_count
		
		withinNeighbourRC_Patch = patch[match(withinNeighbourRC, maskRC)]
			index4neighbour = match(withinNeighbourRC_Patch, orderedPatch)
			index4itself = match(currentPatchID, orderedPatch)
			current_patch_info = patchInfo[[index4itself]]
			# 0 = land
			# 1 = stream
			# 2 = road
			# 3 
			# 4 = roof
		drainage_type = ifelse(current_patch_info[11]>0,1,ifelse(current_patch_info[12]>0,2,0))					
		
		#what = cbind(withinNeighbourRC, withinNeighbourRC_edge, withinNeighbourRC_prefer, withinNeighbourRC_Patch, index4neighbour)
		neighbourLength = 1:length(withinNeighbourRC)	
		neighbourOrder = match(withinNeighbourRC,unique(withinNeighbourRC))
		allNeighbourInfo = simplify2array(tapply(neighbourLength, INDEX=neighbourOrder, function(jj){
			## exploring information between "current" and neighbour(jj)
				# index4neighbour[jj][1] # index of neighbour(jj) in "patchInfo" list
				# withinNeighbourRC_edge[jj] # all edges between current and neighbour(jj)
				# withinNeighbourRC_prefer[jj] # all prefers between current and neighbour(jj)
			
			neighbor_patch_info = patchInfo[[ index4neighbour[jj][1] ]];
			idiffDEM = current_patch_info[2]-neighbor_patch_info[2]
			idiffDEM = ifelse(idiffDEM<0,0, idiffDEM)
			
			return <- c(
				neighbor_patch_info[c(1,7,6)], #patchID, zone, hill
				sqrt((neighbor_patch_info[3]-current_patch_info[3])^2 + 
					(neighbor_patch_info[4]-current_patch_info[4])^2), # distance
					idiffDEM, #rise (normal)
					ifelse(mean(withinNeighbourRC_prefer[jj])>0 & idiffDEM==0, flatDEMdrop, idiffDEM), #rise (prefer)
				sum(withinNeighbourRC_edge[jj]) #edge
			)
		}))#tapply <<--- not in a right order
		
		rise_jj = allNeighbourInfo[ifelse(sum(allNeighbourInfo[5,])==0,6,5),]
		slope_jj = rise_jj/allNeighbourInfo[4,]
		gamma_jj = slope_jj*allNeighbourInfo[7,]
		
		neighbor_frac_gamma = gamma_jj/ifelse(sum(gamma_jj)>0,sum(gamma_jj),1)
		total_perimeter = sum( allNeighbourInfo[7, slope_jj>0] )
		total_gamma = sum(gamma_jj)/total_perimeter*current_patch_info[13]*cellarea; # currrent CF calculation
		if(drainage_type==1) total_gamma = current_patch_info[14]*current_patch_info[13]*cellarea; # special for stream
			
				
		# current patch:[patch,zone,hill,x,y,z,acc_area,area,drainage_type,gamma,#neighbor]
		flow_table_buff <<- c(flow_table_buff, paste(
			paste(current_patch_info[c(1,7,6)], collapse=' '),
			paste(sprintf('%.1f',current_patch_info[c(8,9,2)]), collapse=' '),
			paste(sprintf('%.1f',current_patch_info[c(10,13)]), collapse=' '),
			drainage_type, 
			total_gamma,length(withinNeighbourRC) ));
		
		# patches to go to [patch,zone,hill,?]
		flow_table_buff <<- c(flow_table_buff, paste(
			allNeighbourInfo[1,],
			allNeighbourInfo[2,],
			allNeighbourInfo[3,], 
			neighbor_frac_gamma,sep=' '));
		
		if(drainage_type==2) flow_table_buff <<- c(flow_table_buff, 
			paste(patch_info_lowest[1], 
			patch_info_lowest[7], 
			patch_info_lowest[6], 
			roadWidth,sep=' '))#road
		
		return <- 1;
	})#tapply
	
	
	## Part 3: writing output flow table

	write(flow_table_buff, paste(projectFolder,'/rhessys/flow/flowtable_sub.txt',sep=''), ncolumns=1)
	
	
