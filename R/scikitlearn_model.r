#' Wrapper for Python Scikit-Learn Models
#'
#' scikit-learn models may be loaded into R environment like any other Python object. This function helps to inspect performance of Python model
#' and compare it with other models, using R tools like DALEX. This function creates an object that is easy accessible R version of scikit-learn model
#' exported from Python via pickle file.
#'
#' @usage scikitlearn_model(path)
#'
#' @param path a path to the pickle file
#' @param yml a path to the yml file. Conda virtual env will be recreated from this file. If OS is Windows conda has to be added to the PATH first
#' @param condaenv If yml param is provided, a path to the main conda folder. If yml is null, a name of existing conda environment.
#' @param env A path to python virtual environment
#' @param explain indicator if explainer should be returned. When TRUE, requires `data` and `y` to be not NULL. Default is FALSE.
#' @param data test data set that will be passed to explainer if `explain` is TRUE
#' @param y vector that will be passed to explainer if `explain` is TRUE
#'
#'
#' @author Szymon Maksymiuk
#'
#'
#' @return An object of the class 'scikitlearn_model' or 'explainer'. Depends on explainer param.
#'
#' scikitlearn_model is a list with following fields:
#'
#' \itemize{
#' \item \code{model} it is original model received vie reticiulate function. Use it for computations.
#' \item \code{predict_function} predict function extracted from original model. It is adjusted to DALEX demands and therfore fully compatibile.
#' \item \code{type} type model, classification or regression
#' \item \code{params} object of class `scikitlearn_set` which in fact is list that consist of parameters of our model.
#' \item \code{label} name of model
#'
#' }
#'
#' \bold{Example of Python code}\cr
#'
#' from pandas import DataFrame, read_csv \cr
#' import pandas as pd\cr
#' import pickle\cr
#' import sklearn.ensemble\cr
#' model = sklearn.ensemble.GradientBoostingClassifier() \cr
#' model = model.fit(titanic_train_X, titanic_train_Y)\cr
#' pickle.dump(model, open("gbm.pkl", "wb"), protocol = 2)\cr
#' \cr
#' \cr
#'
#' \bold{Errors use case}\cr
#' Here is shortened version of
#'
#'
#' @examples
#' # Usage with explain()
#' have_sklearn <- reticulate::py_module_available("sklearn.ensemble")
#' library("DALEX")
#' library("reticulate")
#'
#' if(have_sklearn) {
#'    # Explainer build (Keep in mind that 18th column is target)
#'    titanic_test <- read.csv(system.file("extdata", "titanic_test.csv", package = "DALEX"))
#'    # Model was built under Python 3.7 and scikitlearn 0.20.3
#'    # Keep in mind that when pickle is being built and loaded,
#'    # not only Python version but libraries versions has to match aswell
#'    model <- scikitlearn_model(system.file("extdata", "gbm.pkl", package = "DALEX"))
#'    explainer <- explain(model = model, data = titanic_test[,1:17], y = titanic_test$survived)
#'    print(model_performance(explainer))
#'
#'    # Predictions with newdata
#'    predictions <- model$predict_function(model$model, titanic_test[,1:17])
#'
#' } else {
#'   print('Python testing environment is required.')
#' }
#'
#'
#' @rdname scikitlearn_model
#' @export
#'
scikitlearn_model <-
  function(path,
           yml = NULL,
           condaenv = NULL,
           env = NULL,
           explain = FALSE,
           data = NULL,
           y = NULL) {
    if (!is.null(condaenv) & !is.null(env)) {
      stop("Only one argument from condaenv and env can be different from NULL")
    }
    if (!is.null(yml) &
        is.null(condaenv) & .Platform$OS.type == "unix") {
      stop("You have to provide condaenv parameter with yml when using unix-like OS")
    }

    if (!is.null(yml)) {
    name <- crete_env(yml, condaenv)
      tryCatch(
        reticulate::use_condaenv(name, required = TRUE),
        error = function(e) {
          warning(e, call. = FALSE)
          stop(
            "reticulate is unable to set new environment due to already using other python.exe, please restart R session. See warnings() for original error",
            call. = FALSE
          )
        }
      )

    }

    if (!is.null(condaenv) & is.null(yml)) {
      tryCatch(
        reticulate::use_condaenv(condaenv, required = TRUE),
        error = function(e) {
          warning(e, call. = FALSE)
          stop(
            "reticulete is unable to set new environment due to already using other python.exe, please restart R session. See warnings() for original error",
            call. = FALSE
          )
        }
      )



    }

    if (!is.null(env)) {
      tryCatch(
        reticulate::use_virtualenv(env, required = TRUE),
        error = function(e) {
          warning(e, call. = FALSE)
          stop(
            "reticulete is unable to set new environment due to already using other python.exe, please restart R session. See warnings() for original error",
            call. = FALSE
          )
        }
      )
    }




    model <- dalex_load_object(path)

    # params are represented as one longe string
    params <- model$get_params
    # taking first element since strsplit() returns list of vectors
    params <- strsplit(as.character(params), split = ",")[[1]]
    # replacing blanks and other signs that we don't need and are pasted with params names
    params <-
      gsub(params,
           pattern = "\n",
           replacement = "",
           fixed = TRUE)
    params <-
      gsub(params,
           pattern = " ",
           replacement = "",
           fixed = TRUE)
    # splitting after "=" mark and taking first element (head(n = 1L)) provides as with params names
    params <- lapply(strsplit(params, split = "="), head, n = 1L)
    # removing name of function from the first parameter
    params[[1]] <- strsplit(params[[1]], split = "\\(")[[1]][2]
    # setting freshly extracted parameters names as labels for list
    names(params) <- as.character(params)
    #extracting parameters value
    params <- lapply(params, function(x) {
      model[[x]]
    })

    class(params) <- "scikitlearn_set"

    #name of our model
    label <- strsplit(as.character(model), split = "\\(")[[1]][1]

    if ("predict_proba" %in% names(model)) {
      predict_function <- function(model, newdata) {
        # we take second cloumn which indicates probability of `1` to adapt to DALEX predict functions (yhat)
        model$predict_proba(newdata)[, 2]
      }
      type = "classification"
    } else{
      predict_function <- function(model, newdata) {
        model$predict(newdata)
      }
      type = "regression"
    }

    scikitlearn_model <- list(
      label = label,
      type = type,
      params = params,
      predict_function = predict_function,
      model = model
    )
    class(scikitlearn_model) <- "scikitlearn_model"
    scikitlearn_model

  }
