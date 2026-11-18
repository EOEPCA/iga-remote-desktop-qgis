
# syntax=docker/dockerfile:1.7

# ============================================================
# QGIS Remote Desktop Development Environment
#
# Base:
#   Hardened Jupyter EO / XFCE / TurboVNC
#   Ubuntu 24.04
#   Jupyter Python 3.13
#
# QGIS:
#   Native Ubuntu APT installation
#   System Python 3.12
#
# Python tooling:
#   uv
#
# No Mamba or Conda commands.
# ============================================================

ARG BASE_IMAGE=ghcr.io/eoepca/iga-remote-desktop:latest-dev
FROM ${BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_NO_PROGRESS=1

# ------------------------------------------------------------
# System dependencies and QGIS
#
# Install QGIS and Python bindings together to ensure
# compatible Qt, GDAL, GEOS, PROJ and SIP libraries.
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update -o Acquire::Retries=5; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wmctrl \
      libgl1 \
      libegl1 \
      libxkbcommon-x11-0 \
      libxcb-xinerama0 \
      libxcb-cursor0 \
      python3 \
      python3-venv \
      python3-pip \
      python3-qgis \
      qgis; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# uv installation
#
# Install uv using Python packaging in the inherited
# Jupyter Python 3.13 environment.
# ------------------------------------------------------------
ARG UV_VERSION=0.9.13

RUN set -eux; \
    /opt/conda/bin/python -m pip install \
      --no-cache-dir \
      "uv==${UV_VERSION}"; \
    /opt/conda/bin/python -m pip check; \
    /opt/conda/bin/uv --version


# ------------------------------------------------------------
# QGIS runtime paths
#
# QGIS uses Ubuntu system Python, not Jupyter Python.
# Avoid globally overriding PYTHONPATH.
# ------------------------------------------------------------
ENV QGIS_PREFIX_PATH=/usr

ENV QGIS_PLUGINPATH=/opt/qgis/plugins

ENV QGIS_PLUGIN_MANAGER_CACHE_DIR=/opt/qgis/cache


# ------------------------------------------------------------
# QGIS plugin directories
# ------------------------------------------------------------
RUN set -eux; \
    mkdir -p \
      /opt/qgis/plugins \
      /opt/qgis/cache \
      /opt/qgis/plugin-manager; \
    chmod 755 \
      /opt/qgis \
      /opt/qgis/plugins \
      /opt/qgis/cache \
      /opt/qgis/plugin-manager


# ------------------------------------------------------------
# QGIS Plugin Manager
#
# Install using uv in a dedicated Python environment.
# The venv uses Python 3.12.
# ------------------------------------------------------------
ARG QGIS_PLUGIN_MANAGER_VERSION=1.7.5

RUN set -eux; \
    /opt/conda/bin/uv venv \
      --python /usr/bin/python3 \
      --system-site-packages \
      /opt/qgis/plugin-manager/.venv; \
    /opt/conda/bin/uv pip install \
      --python /opt/qgis/plugin-manager/.venv/bin/python \
      "qgis-plugin-manager==${QGIS_PLUGIN_MANAGER_VERSION}"; \
    /opt/conda/bin/uv pip check \
      --python /opt/qgis/plugin-manager/.venv/bin/python


# ------------------------------------------------------------
# QGIS launcher
#
# Run system QGIS without Conda's Python or Qt environment
# interfering with Ubuntu libraries.
# ------------------------------------------------------------
RUN set -eux; \
    printf '%s\n' \
      '#!/bin/sh' \
      'unset PYTHONPATH' \
      'unset PYTHONHOME' \
      'unset QT_QPA_PLATFORM_PLUGIN_PATH' \
      'unset QT_PLUGIN_PATH' \
      'export QGIS_PREFIX_PATH=/usr' \
      'export QGIS_PLUGINPATH=/opt/qgis/plugins' \
      'exec /usr/bin/qgis "$@"' \
      > /usr/local/bin/qgis-launch; \
    chmod 755 /usr/local/bin/qgis-launch


# ------------------------------------------------------------
# QGIS Plugin Manager wrapper
# ------------------------------------------------------------
RUN set -eux; \
    printf '%s\n' \
      '#!/bin/sh' \
      'exec /opt/qgis/plugin-manager/.venv/bin/qgis-plugin-manager "$@"' \
      > /usr/local/bin/qgis-plugin-manager; \
    chmod 755 /usr/local/bin/qgis-plugin-manager


# ------------------------------------------------------------
# QGIS desktop integration
#
# Use the wrapper to launch the system QGIS application.
# ------------------------------------------------------------
COPY --chmod=644 qgis.desktop \
    /etc/xdg/autostart/qgis.desktop

COPY --chmod=644 qgis.desktop \
    /usr/share/applications/qgis.desktop

# Replace Exec in both desktop entries.
RUN set -eux; \
    sed -i \
      's|^Exec=.*|Exec=/usr/local/bin/qgis-launch|' \
      /etc/xdg/autostart/qgis.desktop; \
    sed -i \
      's|^Exec=.*|Exec=/usr/local/bin/qgis-launch|' \
      /usr/share/applications/qgis.desktop


# ------------------------------------------------------------
# STAC API Browser
#
# Install through QGIS Plugin Manager.
# ------------------------------------------------------------
WORKDIR /opt/qgis

RUN set -eux; \
    qgis-plugin-manager init; \
    qgis-plugin-manager update; \
    qgis-plugin-manager install "STAC API Browser"; \
    qgis-plugin-manager list


# ------------------------------------------------------------
# Permissions
#
# System applications are read-only at runtime.
# ------------------------------------------------------------
RUN set -eux; \
    chmod -R a+rX /opt/qgis; \
    fix-permissions "${HOME}"


# ------------------------------------------------------------
# Build-time smoke tests
# ------------------------------------------------------------
RUN set -eux; \
    /opt/conda/bin/python -c \
      'import sys; assert sys.version_info[:2] == (3, 13)'; \
    /usr/bin/python3 -c \
      'import sys; assert sys.version_info[:2] == (3, 12)'; \
    /opt/conda/bin/uv --version; \
    /opt/qgis/plugin-manager/.venv/bin/python -c \
      'import qgis.core; print("QGIS Python bindings OK")'; \
    QT_QPA_PLATFORM=offscreen \
      /usr/local/bin/qgis-launch --version; \
    qgis-plugin-manager --help; \
    test -d /opt/qgis/plugins


# ------------------------------------------------------------
# Restore standard Jupyter working directory and user
# ------------------------------------------------------------
WORKDIR /home/${NB_USER}

USER ${NB_USER}
