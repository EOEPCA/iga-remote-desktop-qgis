
# syntax=docker/dockerfile:1.7

# ============================================================
# QGIS remote desktop development environment
#
# Base:
#   Upgraded EO Jupyter / XFCE / TurboVNC image
#   Python 3.13
#   Nextcloud 33.0.7-20260629
#
# Build the base image first and publish it under the
# reference below.
# ============================================================

ARG BASE_IMAGE=ghcr.io/eoepca/iga-remote-desktop:1.3.0
FROM ${BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# QGIS runtime system dependencies
# ------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libgl1-mesa-dev \
       ocl-icd-opencl-dev \
       wmctrl \
       libgl1 \
       libegl1 \
       libxkbcommon-x11-0 \
       libxcb-xinerama0 \
       libxcb-cursor0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# QGIS Conda environment
#
# Keep QGIS 3.44.7.
# Let conda-forge resolve the matching Python and Qt ABI.
# ------------------------------------------------------------
ARG QGIS_VERSION=3.44.7
ARG QGIS_PYTHON_VERSION=3.13

RUN mamba create -y \
      -n env_qgis \
      --override-channels \
      -c conda-forge \
      "python=${QGIS_PYTHON_VERSION}" \
      "qgis=${QGIS_VERSION}" \
      pip \
    && mamba clean --all --yes


# ------------------------------------------------------------
# Activate QGIS environment by default
# ------------------------------------------------------------
ENV PATH="/opt/conda/envs/env_qgis/bin:${PATH}"

ENV QGIS_PREFIX_PATH="/opt/conda/envs/env_qgis"

ENV PYTHONPATH="/opt/conda/envs/env_qgis/share/qgis/python"

# Avoid Qt conflicts from the base environment.
ENV QT_QPA_PLATFORM_PLUGIN_PATH="/opt/conda/envs/env_qgis/plugins"


# ------------------------------------------------------------
# QGIS desktop integration
# ------------------------------------------------------------
COPY qgis.desktop \
    /etc/xdg/autostart/qgis.desktop

COPY qgis.desktop \
    /usr/share/applications/qgis.desktop


# ------------------------------------------------------------
# QGIS plugin manager
#
# Install inside env_qgis, not into the Jupyter base Python.
# ------------------------------------------------------------
ARG QGIS_PLUGIN_MANAGER_VERSION=1.7.5

RUN /opt/conda/envs/env_qgis/bin/python -m pip install \
      --no-cache-dir \
      "qgis-plugin-manager==${QGIS_PLUGIN_MANAGER_VERSION}" \
    && /opt/conda/envs/env_qgis/bin/python -m pip check


# ------------------------------------------------------------
# QGIS plugin installation
# ------------------------------------------------------------
RUN qgis-plugin-manager init \
    && qgis-plugin-manager update \
    && qgis-plugin-manager install "STAC API Browser"


# ------------------------------------------------------------
# Permissions
# ------------------------------------------------------------
RUN chown -R "${NB_UID}:${NB_GID}" "${HOME}"


# ------------------------------------------------------------
# Build-time smoke tests
# ------------------------------------------------------------
RUN python --version \
    && qgis --version \
    && qgis-plugin-manager --help \
    && python -c \
      "from qgis.core import QgsApplication; print('QGIS Python bindings OK')"


# ------------------------------------------------------------
# Restore Jupyter non-root user
# ------------------------------------------------------------
USER ${NB_USER}
