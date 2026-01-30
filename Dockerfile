FROM ghcr.io/eoepca/iga-remote-desktop:1.2.0

USER root

RUN apt update && apt-get install -y libgl1-mesa-dev ocl-icd-opencl-dev wmctrl && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG QGIS_VERSION=3.44.7

RUN mamba create -n env_qgis -c conda-forge "qgis==$QGIS_VERSION" && mamba clean -a
#&& cd /opt/conda/lib && ln -s  /opt/conda/lib/libprotobuf.so.24 libprotobuf-lite.so.23 && conda clean -a

ENV PATH=/opt/conda/envs/env_qgis/bin:$PATH

RUN chown -R $NB_UID:$NB_GID $HOME

COPY qgis.desktop /etc/xdg/autostart/qgis.desktop
COPY qgis.desktop /usr/share/applications/qgis.desktop



ENV PYTHONPATH=/opt/conda/envs/env_qgis/share/qgis/python
ARG QGIS_PLUGIN_MANAGER_VERSION=1.7.5
RUN pip3 install qgis-plugin-manager==$QGIS_PLUGIN_MANAGER_VERSION \
  && qgis-plugin-manager init \
  && qgis-plugin-manager update \
  && qgis-plugin-manager install "STAC API Browser" 

USER $NB_USER



