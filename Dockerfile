FROM centos:7
ARG arg
RUN if [ "x$arg" = "x" ] ; then \
    echo Argument not provided; \
  else \
    echo Argument is $arg; \
  fi