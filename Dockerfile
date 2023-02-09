FROM eoepca/iga-remote-desktop

USER root

RUN apt update && apt-get install -y libgl1-mesa-dev ocl-icd-opencl-dev 

RUN conda create -n env_qgis -c conda-forge "qgis>=3.22.0" #&& cd /opt/conda/lib && ln -s  /opt/conda/lib/libprotobuf.so.24 libprotobuf-lite.so.23 && conda clean -a

ENV PATH=/opt/conda/envs/env_qgis/bin:$PATH

RUN chown -R $NB_UID:$NB_GID $HOME

USER $NB_USER
