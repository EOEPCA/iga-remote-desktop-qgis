FROM eoepca/iga-remote-desktop:1.1.2

USER root

RUN apt update && apt-get install -y libgl1-mesa-dev ocl-icd-opencl-dev wmctrl

RUN mamba create -n env_qgis -c conda-forge "qgis>=3.38.3" #&& cd /opt/conda/lib && ln -s  /opt/conda/lib/libprotobuf.so.24 libprotobuf-lite.so.23 && conda clean -a

ENV PATH=/opt/conda/envs/env_qgis/bin:$PATH

ADD qgis.desktop /etc/xdg/autostart/qgis.desktop

RUN chown -R $NB_UID:$NB_GID $HOME

USER $NB_USER
