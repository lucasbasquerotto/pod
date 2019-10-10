FROM {{ params.toolbox_image }}:{{ params.toolbox_version }}

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/toolbox/s3cmd.cfg /root/.s3cfg
COPY $POD_ENV_DIR/toolbox/aws/ /root/.aws/