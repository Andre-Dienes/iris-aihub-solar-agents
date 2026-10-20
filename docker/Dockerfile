# IRIS AI Hub solar agents demo
#
# The AI Hub classes (%AI.*) ship only in the InterSystems IRIS AI Hub Early Access builds
# (https://evaluation.intersystems.com/Eval/early-access/AIHub). Load the image tarball with
# `docker load -i <file>.tar.gz` and set IRIS_IMAGE in docker/.env to its tag.
# Prefer the irishealth-community AI images: they include the web gateway used by /api/solar and /mcp/solar.
ARG IMAGE=intersystems/irishealth-community:2026.3.0AI.136.0
FROM $IMAGE

USER root
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} docker/iris.script /home/irisowner/demo/iris.script
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} docker/entrypoint.sh /entrypoint.sh
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} src /src
RUN chmod +x /entrypoint.sh

USER ${ISC_PACKAGE_MGRUSER}
WORKDIR /home/irisowner
RUN iris start IRIS quietly \
 && iris session IRIS < /home/irisowner/demo/iris.script \
 && iris stop IRIS quietly

EXPOSE 1972 52773 8888
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]
