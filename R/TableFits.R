InitTableFits <- function(
  modelTypes,
  fitMappingsPrev = NULL,
  tableFitsPrev = fitMappingsPrev$tableFits,
  modelTypesInTableFitsPrev = NULL,
  verbose = FALSE) {

  # prevent 'no visible binding' notes
  hashCodeTree <- hashCodeStartingNodesRegimesLabels <-
    hashCodeMapping <- NULL

  tableFits <- tableFitsPrev

  if(!is.null(fitMappingsPrev)) {
    tableFits <- tableFitsPrev <- fitMappingsPrev$tableFits
    if(!identical(modelTypes, fitMappingsPrev$arguments$modelTypes)) {

      # this should remap the model-type indices in the fit vectors, show
      # table fits is correctly converted.
      tableFits <- RetrieveFittedModelsFromFitVectors(
        fitMappings = fitMappingsPrev, tableFits = tableFitsPrev,
        modelTypesNew = modelTypes)
    }
  }

  if(!is.data.table(tableFits)) {
    if(verbose) {
      cat("Initiating tableFits...\n")
    }
    tableFits = data.table(hashCodeTree = character(),
                           hashCodeStartingNodesRegimesLabels = character(),
                           hashCodeMapping = character(),
                           treeEDExpression = character(),
                           startingNodesRegimesLabels = list(),
                           mapping = list(),
                           fitVector = list(),
                           logLik = double(),
                           df = integer(),
                           nobs = integer(),
                           score = double(),
                           duplicated = logical())
  }

  setkey(tableFits, hashCodeTree,hashCodeStartingNodesRegimesLabels,hashCodeMapping )
  attr(tableFits, "modelTypes") <- modelTypes
  tableFits
}

#' @importFrom data.table is.data.table
UpdateTableFits <- function(tableFits, newFits) {

  # prevent 'no visible binding' notes
  score <- hashCodeTree <- hashCodeStartingNodesRegimesLabels <-
    hashCodeMapping <- NULL

  if(!is.data.table(newFits) && !is.data.table(tableFits)) {
    stop("Both newFits and tableFits are not data.table objects!")
  } else if(!is.data.table(newFits)) {
    # swap the two arguments
    newFits2 <- tableFits
    tableFits <- newFits
    newFits <- newFits2
  }
  if(is.null(tableFits) || !is.data.table(tableFits) || nrow(tableFits) == 0) {
    tableFits <- newFits
  } else {
    #nrow(tableFits) > 0
    tableFits <- rbindlist(list(newFits, tableFits), use.names = TRUE)
  }

  tableFits[, .SD[which.min(score)], keyby = list(
    hashCodeTree, hashCodeStartingNodesRegimesLabels, hashCodeMapping)]
}

#' Retrieve the ML fits from the fitVectors column in a table of fits.
#'
#' @param fitMappings an object of S3 class PCMFitModelMappings.
#' @param tableFits a data.table
#' @param modelTypes a character vector of model types. Default:
#' \code{fitMappings$arguments$modelTypes}.
#' @param modelTypesNew NULL or a character vector containing all model-types in
#'  fitMappings$arguments$modelTypes and, eventually, additional model-types.
#' @param argsMixedGaussian a list of arguments passed to the
#' \code{\link{MixedGaussian}}.
#' Default: \code{fitMappings$arguments$argsMixedGaussian}.
#' @param setAttributes logical indicating if an X and tree attribute should be
#' set to each model-object. This is used for later evaluation of the
#' log-likelihood of the score for the model on the given tree and
#' data. Using a global tree for that is a bad idea, because the model may be
#' fit for a subtree, i.e. clade. Default FALSE.
#' @param X a \code{k x N} numerical matrix with possible \code{NA} and \code{NaN} entries. Each
#' column of X contains the measured trait values for one species (tip in tree).
#' Missing values can be either not-available (\code{NA}) or not existing
#' (\code{NaN}). Default: \code{fitMappings$X}.
#' @param tree a phylo object with N tips. Default:
#' \code{fitMappings$tree}.
#' @param SE a k x N matrix specifying the standard error for each measurement in
#' X. Alternatively, a k x k x N cube specifying an upper triangular k x k
#' factor of the variance covariance matrix for the measurement error
#' for each node i=1, ..., N.
#' Default: \code{fitMappings$SE}.
#' @return a copy of tableFits with added column "model" and, if necessary,
#' updated integer model-type indices in the "fitVector" column.
#' @importFrom PCMBase MixedGaussian PCMTreeEvalNestedEDxOnTree
#' @importFrom data.table setnames
#' @export
RetrieveFittedModelsFromFitVectors <- function(
  fitMappings,

  tableFits = fitMappings$tableFits,
  modelTypes = fitMappings$arguments$modelTypes,
  modelTypesNew = NULL,
  argsMixedGaussian = fitMappings$arguments$argsMixedGaussian,

  X = fitMappings$X,
  tree = fitMappings$tree,
  SE = fitMappings$SE,

  setAttributes = FALSE) {

  # prevent 'no visible binding' notes
  fittedModel <- fitVector <- treeEDExpression <-
    startingNodesRegimesLabels <- NULL

  if(is.null(tableFits$score)) {
    # in previous versions the column score was named aic
    setnames(tableFits, "aic", "score")
  }

  # Copy all arguments into a list
  # We establish arguments$<argument-name> as a convention for accessing the
  # original argument value.
  arguments <- as.list(environment())

  tableFits2 <- copy(tableFits)
  tableFits2[, fittedModel:=lapply(seq_len(.N), function(i, numRows) {
    model <- do.call(
      PCMLoadMixedGaussianFromFitVector,
      c(list(fitVector = fitVector[[i]],
             modelTypes = modelTypes,
             k = nrow(X)),
        argsMixedGaussian)
    )
    if(!is.null(modelTypesNew)) {
      # update the modelTypes and mapping attribute of the model appropriately
      if(is.character(modelTypesNew) && all(modelTypes %in% modelTypesNew) ) {
        # note that the constructor MixedGaussian accepts character vector as well as integer vector for mapping.
        mappingNew <- attr(model, "modelTypes")[attr(model, "mapping")]
        modelNew <- do.call(
          MixedGaussian,
          c(list(k = nrow(X),
                 modelTypes = modelTypesNew,
                 mapping = mappingNew),
            argsMixedGaussian))
        PCMParamLoadOrStore(modelNew, PCMParamGetShortVector(model), offset = 0, load = TRUE)
        model <- modelNew
      } else {
        stop(
          paste0(
            "RetrieveFittedModels:: if modelTypesNew is not NULL fitMappings$arguments$modelTypes (",
            toString(modelTypes),
            ") should be a subset of modelTypesNew (",
            toString(modelTypesNew), ")."))
      }
    }
    if(setAttributes) {
      tree <- PCMTreeEvalNestedEDxOnTree(
        treeEDExpression[[i]], PCMTree(arguments$tree))
      PCMTreeSetPartition(
        tree, match(startingNodesRegimesLabels[[i]], PCMTreeGetLabels(tree)))
      X <- arguments$X[, tree$tip.label, drop = FALSE]
      SE <- if(is.matrix(arguments$SE)) {
        arguments$SE[, tree$tip.label, drop = FALSE]
      } else {
        arguments$SE[,, tree$tip.label, drop = FALSE]
      }
      if(is.null(SE)) {
        SE <- X
        SE[] <- 0.0
      }
      attr(model, "tree") <- tree
      attr(model, "X") <- X
      attr(model, "SE") <- SE
    }
    if(numRows == 1) {
      list(model)
    } else {
      model
    }
  }, numRows = .N)]

  if(!is.null(modelTypesNew)) {
    # update the fitVectors according to the new modelTypes
    if(is.character(modelTypesNew) && all(modelTypes %in% modelTypesNew) ) {
      # note that the constructor MixedGaussian accepts character vector as well as integer vector for mapping.
      tableFits2[, fitVector:=lapply(seq_len(.N), function(i) {
        treei <- PCMTreeEvalNestedEDxOnTree(
          treeEDExpression[[i]], PCMTree(arguments$tree))
        PCMTreeSetPartition(
          treei, match(startingNodesRegimesLabels[[i]], PCMTreeGetLabels(treei)))
        par <- c(PCMGetVecParamsRegimesAndModels(fittedModel[[i]], treei), numParam = PCMParamCount(fittedModel[[i]]))
        fitVec <- fitVector[[i]]
        fitVec[seq_len(length(par))] <- par
        fitVec
      })]
    } else {
      stop(paste0("RetrieveFittedModels:: if modelTypesNew is not NULL fitMappings$arguments$modelTypes (", toString(modelTypes), ") should be a subset of modelTypesNew (", toString(modelTypesNew), ")."))
    }
  }
  tableFits2
}

#' Retrieve the best fit from a PCMFitMappings object.
#' @param fitMappings an object of S3 class 'PCMFitModelMappings' as returned by
#' \code{\link{PCMFitMixed}}.
#' @param rank an integer. Default: 1.
#' @return a named list.
#' @importFrom data.table setnames
#' @export
RetrieveBestFitScore <- function(fitMappings, rank = 1) {
  # prevent 'no visible binding' notes
  hashCodeTree <- score <- NULL

  if(is.null(fitMappings$tableFits$score)) {
    # the fit was produced with a previous version where the score column
    # was named aic.
    setnames(fitMappings$tableFits, old = "aic", new = "score")
  }



  tableFits <- RetrieveFittedModelsFromFitVectors(
    fitMappings = fitMappings,
    tableFits = fitMappings$tableFits[
      hashCodeTree==fitMappings$hashCodeTree][order(score)][rank],
    setAttributes = TRUE)

  res <- list(
    tree = PCMTree(fitMappings$tree),
    X = fitMappings$X,
    modelTypes = fitMappings$arguments$modelTypes,
    inferredRegimeNodes = tableFits$startingNodesRegimesLabels[[1]],
    inferredMapping = tableFits$mapping[[1]],
    inferredMappingIdx = match(tableFits$mapping[[1]], fitMappings$arguments$modelTypes),
    inferredModel = tableFits$fittedModel[[1]]
  )

  PCMTreeSetLabels(res$tree)
  PCMTreeSetPartition(res$tree, res$inferredRegimeNodes)

  res[["inferredMappedModels"]] <- attr(res$inferredModel, "mapping")[res$tree$edge.regime]
  res
}

# Update with parameters from submodels where the fit of a submodel is better
#' @importFrom PCMBase PCMDefaultObject PCMParamSetByName
UpdateCladeFitsUsingSubModels <- function(
  cladeFits,
  modelTypes,
  subModels,
  argsMixedGaussian,
  metaIFun = PCMInfo,
  scoreFun,
  X, tree, SE,
  verbose = FALSE) {

  # prevent 'no visible binding' notes
  treeEDExpression <- mapping <- modelTypeName <- fittedModel <- fitVector <-
    score <- hashCodeTree <- hashCodeStartingNodesRegimesLabels <-
    hashCodeMapping <- NULL

  cladeFitsNew <- cladeFits[integer(0L)]
  count <- 0L
  cladeRoots <- c()
  listAllowedModelTypesIndices <- list()

  for(modelType in names(subModels)) {
    for(edExpr in unique(cladeFits[, treeEDExpression])) {
      subModelType <- subModels[modelType]

      cladeFits2 <- cladeFits[treeEDExpression == edExpr][
        unlist(mapping) %in% modelTypes[c(modelType, subModelType)]]

      cladeFits2[, modelTypeName:=names(modelTypes)[match(unlist(mapping), modelTypes)]]
      setkey(cladeFits2, modelTypeName)

      cladeRoot <- cladeFits2$startingNodesRegimesLabels[[1L]]

      if(nrow(cladeFits2) == 2L &&
         nrow(cladeFits2[list(modelType)]) == 1L &&
         nrow(cladeFits2[list(subModelType)]) == 1L &&
         cladeFits2[list(modelType), logLik] + 0.1 <
         cladeFits2[list(subModelType), logLik]) {

        cladeFits2Models <- RetrieveFittedModelsFromFitVectors(
          fitMappings = NULL,
          tableFits = cladeFits2,
          modelTypes = modelTypes,
          modelTypesNew = NULL,
          argsMixedGaussian = argsMixedGaussian,

          X = X,
          tree = tree,
          SE = SE,

          setAttributes = TRUE)

        model <- cladeFits2Models[list(modelType), fittedModel[[1]]]
        subModel <- cladeFits2Models[list(subModelType), fittedModel[[1]]]
        model2 <- PCMDefaultObject(spec = attr(model, 'spec'), model = model)
        attributes(model2) <- attributes(model)
        attr(model2, "PCMInfoFun") <- metaIFun(
          X = attr(model2, "X", exact = TRUE),
          tree = attr(model2, "tree", exact = TRUE),
          model = model2,
          SE = attr(model2, "SE", exact = TRUE))
        PCMParamSetByName(model2, subModel, inplace = TRUE, deepCopySubPCMs = TRUE)

        vecModel <- cladeFits2Models[list(modelType)]$fitVector[[1]]
        idxParams <- seq_len(PCMParamCount(model))
        idxLogLik <- length(vecModel) - 3
        idxScore <- length(vecModel)
        vecModel[idxParams] <- unname(PCMParamGetShortVector(model2))
        vecModel[idxLogLik] <- unname(logLik(model2))
        vecModel[idxScore] <- unname(scoreFun(model2))

        # this check is needed because numerical error can cause different
        # likeklihood values on the worker nodes and on the master node. This
        # has been observed in simulations with some extreme cases where
        # the logLik on the master node was much lower than the calculated
        # logLik on the worker node.
        if(vecModel[idxLogLik] > cladeFits2[list(modelType), logLik]) {
          count <- count+1L
          if(verbose) {
            cat(
              count, ". ",
              'treeEDExpr=', edExpr,
              ': substituting parameters for modelType=', modelType,
              '(ll=', toString(cladeFits2[list(modelType), logLik]), ')',
              ' with parameters from subModelType=', subModelType,
              '(ll=', toString(cladeFits2[list(subModelType), logLik]), ')',
              '; after substitution ll=', toString(vecModel[idxLogLik]), '\n')
          }

          cladeFits[
            treeEDExpression == edExpr & sapply(mapping, length) == 1L &
              sapply(mapping, function(.) .[[1]]) == modelTypes[modelType],
            fitVector:=list(list(vecModel))]
          cladeFits[
            treeEDExpression == edExpr & sapply(mapping, length) == 1L &
              sapply(mapping, function(.) .[[1]]) == modelTypes[modelType],
            logLik:=vecModel[[idxLogLik]]]
          cladeFits[
            treeEDExpression == edExpr & sapply(mapping, length) == 1L &
              sapply(mapping, function(.) .[[1]]) == modelTypes[modelType],
            score:=vecModel[[idxScore]]]

          cladeFitsNewEntry <- cladeFits2[list(modelType)]
          cladeFitsNewEntry[, modelTypeName:=NULL]

          cladeFitsNewEntry[,fitVector:=list(list(vecModel))]
          cladeFitsNewEntry[,logLik:=vecModel[[idxLogLik]]]
          cladeFitsNewEntry[,score:=vecModel[[idxScore]]]

          cladeFitsNew <- rbindlist(list(cladeFitsNew, cladeFitsNewEntry))

          cladeRoots <- c(cladeRoots, cladeRoot)
          listAllowedModelTypesIndices[[as.character(cladeRoot)]] <- c(
            listAllowedModelTypesIndices[[as.character(cladeRoot)]],
            match(modelTypes[modelType], modelTypes))

          if(vecModel[idxLogLik] < cladeFits2[list(subModelType), logLik]) {
            attr(subModel, "PCMInfoFun") <- metaIFun(
              X = attr(subModel, "X", exact = TRUE),
              tree = attr(subModel, "tree", exact = TRUE),
              model = subModel,
              SE = attr(subModel, "SE", exact = TRUE))

            logLikSubModelNew <- unname(logLik(subModel))
            scoreSubModelNew <- unname(scoreFun(subModel))

            if(verbose) {
              cat(
                count, ". ",
                'treeEDExpr=', edExpr,
                ': updating logLikelihood and score value for subModelType=', subModelType,
                ': old ll=', toString(cladeFits2[list(subModelType), logLik]), '',
                ' new ll=', toString(logLikSubModelNew), '\n')
            }

            cladeFits[
              treeEDExpression == edExpr & sapply(mapping, length) == 1L &
                sapply(mapping, function(.) .[[1]]) == modelTypes[subModelType],
              logLik:=logLikSubModelNew]
            cladeFits[
              treeEDExpression == edExpr & sapply(mapping, length) == 1L &
                sapply(mapping, function(.) .[[1]]) == modelTypes[subModelType],
              score:=scoreSubModelNew]

          }
        } else {
          attr(subModel, "PCMInfoFun") <- metaIFun(
            X = attr(subModel, "X", exact = TRUE),
            tree = attr(subModel, "tree", exact = TRUE),
            model = subModel,
            SE = attr(subModel, "SE", exact = TRUE))
          # save(
          #   model2, subModel,
          #   file=paste0(
          #     'ModelSubModel', cladeRoot, modelType, subModelType, '.RData'))
          if(verbose) {
            cat(
              count + 1L, ". ",
              'treeEDExpr=', edExpr,
              ': rejected candidate for substitution modelType=', modelType,
              '(ll=', toString(cladeFits2[list(modelType), logLik]), ')',
              ' with parameters from subModelType=', subModelType,
              '(ll=', toString(cladeFits2[list(subModelType), logLik]), ')',
              ';\n after substitution ll(', modelType, ')=',
              toString(vecModel[idxLogLik]),
              '; ll(', subModelType, ')=',
              toString(logLik(subModel)), '\n')
          }
        }
      }
    }
  }
  if(!is.null(cladeFitsNew)) {
    setkey(
      cladeFitsNew,
      hashCodeTree, hashCodeStartingNodesRegimesLabels, hashCodeMapping)
  }
  list(
    cladeFitsNew = cladeFitsNew,
    listPartitions = as.list(unique(cladeRoots)),
    listAllowedModelTypesIndices = listAllowedModelTypesIndices)
}

#' Generate hash codes.
#'
#' @param tree a phylo object
#' @param modelTypes character vector
#' @param startingNodesRegimesLabels a character vector denoting the
#' partition nodes.
#' @param modelMapping an integer or character vector to be matched against
#'  modelTypes
#' @importFrom PCMBase PCMTreeGetPartition PCMTreeGetLabels
#' @importFrom digest digest
#' @return a character vector.
#' @export
HashCodes <- function(
  tree, modelTypes, startingNodesRegimesLabels, modelMapping) {

  orderPNLs <- order(as.integer(startingNodesRegimesLabels))
  list(
    hashCodeTree = digest(PCMTreeToString(tree), serialize = FALSE),
    hashCodeStartingNodesRegimesLabels = digest(
      toString(startingNodesRegimesLabels[orderPNLs]), serialize = FALSE),
    hashCodeMapping = digest(
      toString(MatchModelMapping(modelMapping[orderPNLs], modelTypes)), serialize = FALSE)
  )
}

#' Lookup a fit vector for a given tree and model mapping in a data.table of
#' previously run fits.
#'
#' @inheritParams HashCodes
#' @param tableFits a data.table having at least the following columns:
#' \itemize{
#' \item{hashCodeTree}{an MD5 key column of type character-vector}
#' \item{hashCodePartitionNodeLabels}{an MD5 key column of type character-vector
#'  representing the hash-code of
#'  \code{PCMTreeGetLabels(tree)[PCMTreeGetPartition(tree)]}.}
#' \item{hashCodeMapping}{an MD5 key column of type character-vector}}
#' @param hashCodes the result of calling \code{\link{HashCodes}} on the passed
#' arguments \code{tree, modelTypes, modelMapping}. Default:
#' \code{HashCodes(
#'   tree = tree, modelTypes = modelTypes,
#'   startingNodesRegimesLabels = PCMTreeGetLabels(tree)[PCMTreeGetPartition(tree)],
#'   modelMapping = modelMapping )}.
#' @return the corresponding fit-vector to the given tree and model mapping or
#' if no such entry is found, issues an error.
#' @importFrom digest digest
#' @importFrom data.table setnames
#' @export
LookupFit <- function(
  tree, modelTypes, modelMapping, tableFits,
  hashCodes = HashCodes(tree = tree,
                        modelTypes = modelTypes,
                        startingNodesRegimesLabels =
                          PCMTreeGetLabels(tree)[PCMTreeGetPartition(tree)],
                        modelMapping = modelMapping )) {
  tableFits[hashCodes, , mult="first", nomatch=0]
}
