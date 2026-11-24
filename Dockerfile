
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
#TODO pin exact iga-remote-desktop ver, e.g. 1.3.0
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
# QGIS Long Term Release (LTR), Solothurn.
ARG QGIS_VERSION=3.44.15
ARG GDAL_VERSION=3.8.4
ARG QGIS_REPOSITORY=https://qgis.org/ubuntu-ltr
ARG QGIS_ARCHIVE_KEYRING_URL=https://download.qgis.org/downloads/qgis-archive-keyring.gpg
ARG GDAL_SOURCE_URL=https://download.osgeo.org/gdal/3.8.4/gdal-3.8.4.tar.xz
ARG APACHE_ARROW_SOURCE_URL=https://packages.apache.org/artifactory/arrow/ubuntu/apache-arrow-apt-source-latest-noble.deb
ARG APACHE_ARROW_VERSION=16.1.0-1

RUN set -eux; \
    apt-get update -o Acquire::Retries=5; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget; \
    install -d -m 755 /etc/apt/keyrings; \
    curl --fail --silent --show-error --location \
      "${QGIS_ARCHIVE_KEYRING_URL}" \
      --output /etc/apt/keyrings/qgis-archive-keyring.gpg; \
    . /etc/os-release; \
    test "${VERSION_CODENAME}" = noble; \
    printf '%s\n' \
      'Types: deb' \
      "URIs: ${QGIS_REPOSITORY}" \
      "Suites: ${VERSION_CODENAME}" \
      "Architectures: $(dpkg --print-architecture)" \
      'Components: main' \
      'Signed-By: /etc/apt/keyrings/qgis-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/qgis.sources; \
    wget --quiet --output-document /tmp/apache-arrow-apt-source.deb \
      "${APACHE_ARROW_SOURCE_URL}"; \
    apt-get install -y --no-install-recommends \
      /tmp/apache-arrow-apt-source.deb; \
    apt-get update -o Acquire::Retries=5; \
    qgis_package_version="$(apt-cache madison qgis \
      | awk -v version="${QGIS_VERSION}" '$3 == version || $3 ~ (":" version "\\+") { print $3; exit }')"; \
    test -n "${qgis_package_version}"; \
    python_qgis_package_version="$(apt-cache madison python3-qgis \
      | awk -v version="${QGIS_VERSION}" '$3 == version || $3 ~ (":" version "\\+") { print $3; exit }')"; \
    test -n "${python_qgis_package_version}"; \
    test "${python_qgis_package_version}" = "${qgis_package_version}"; \
    apt-get install -y --no-install-recommends \
      wmctrl \
      libgl1 \
      libegl1 \
      libxkbcommon-x11-0 \
      libxcb-xinerama0 \
      libxcb-cursor0 \
      python3 \
      python3-venv \
      python3-pip \
      gdal-bin \
      python3-gdal \
      libgdal-dev \
      "libarrow-dev=${APACHE_ARROW_VERSION}" \
      "libarrow-acero-dev=${APACHE_ARROW_VERSION}" \
      "libarrow-dataset-dev=${APACHE_ARROW_VERSION}" \
      "libparquet-dev=${APACHE_ARROW_VERSION}" \
      build-essential \
      cmake \
      pkg-config \
      "qgis-common=${qgis_package_version}" \
      "qgis-providers=${qgis_package_version}" \
      "qgis-providers-common=${qgis_package_version}" \
      "python3-qgis-common=${python_qgis_package_version}" \
      "python3-qgis=${python_qgis_package_version}" \
      "qgis=${qgis_package_version}"; \
    test "$(gdal-config --version)" = "${GDAL_VERSION}"; \
    mkdir -p /tmp/gdal-${GDAL_VERSION} /tmp/gdal-${GDAL_VERSION}-build; \
    curl --fail --silent --show-error --location \
      "${GDAL_SOURCE_URL}" \
      | tar --extract --xz --strip-components=1 \
          --directory /tmp/gdal-${GDAL_VERSION}; \
    cmake \
      -S /tmp/gdal-${GDAL_VERSION} \
      -B /tmp/gdal-${GDAL_VERSION}-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/usr \
      -DArrow_DIR=/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/cmake/Arrow \
      -DParquet_DIR=/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/cmake/Parquet \
      -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
      -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
      -DGDAL_USE_ARROW=ON \
      -DGDAL_USE_PARQUET=ON \
      -DGDAL_USE_ARROWDATASET=ON \
      -DOGR_ENABLE_DRIVER_PARQUET=ON \
      -DOGR_ENABLE_DRIVER_PARQUET_PLUGIN=ON \
      -DCMAKE_INSTALL_PREFIX=/usr; \
    cmake --build /tmp/gdal-${GDAL_VERSION}-build \
      --target ogr_Parquet \
      --parallel "$(nproc)"; \
    parquet_plugin="$(find /tmp/gdal-${GDAL_VERSION}-build \
      -type f -name 'ogr_Parquet.so' -print -quit)"; \
    test -n "${parquet_plugin}"; \
    install -D -m 755 "${parquet_plugin}" \
      "/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/gdalplugins/ogr_Parquet.so"; \
    ldconfig; \
    rm -rf \
      /tmp/apache-arrow-apt-source.deb \
      /tmp/gdal-${GDAL_VERSION} \
      /tmp/gdal-${GDAL_VERSION}-build; \
      apt-get purge -y \
      build-essential \
      cmake \
      pkg-config \
      libgdal-dev \
      libarrow-dev \
      libarrow-acero-dev \
      libarrow-dataset-dev \
      libparquet-dev \
      curl \
      wget; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# uv installation
#
# Install uv using Python packaging in the inherited
# Jupyter Python 3.13 environment.
# ------------------------------------------------------------
ARG UV_VERSION=0.13.9

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
ARG DUCKDB_VERSION=1.4.4

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
COPY qgis.desktop /etc/xdg/autostart/qgis.desktop

COPY qgis.desktop /usr/share/applications/qgis.desktop

# Replace Exec in both desktop entries.
RUN set -eux; \
    chmod 644 \
      /etc/xdg/autostart/qgis.desktop \
      /usr/share/applications/qgis.desktop; \
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
    retry_plugin_install() { \
      plugin_name="$1"; \
      attempt=1; \
      while ! qgis-plugin-manager install "${plugin_name}"; do \
        if [ "${attempt}" -ge 5 ]; then \
          echo "Failed to install QGIS plugin after ${attempt} attempts: ${plugin_name}" >&2; \
          return 1; \
        fi; \
        sleep_seconds=$((attempt * 5)); \
        echo "Retrying QGIS plugin installation in ${sleep_seconds}s: ${plugin_name}" >&2; \
        sleep "${sleep_seconds}"; \
        attempt=$((attempt + 1)); \
      done; \
    }; \
    qgis-plugin-manager init; \
    qgis-plugin-manager update; \
    retry_plugin_install "STAC API Browser"; \
    /opt/conda/bin/uv pip install \
      --system \
      --break-system-packages \
      --python /usr/bin/python3 \
      "duckdb==${DUCKDB_VERSION}"; \
    /usr/bin/python3 -c \
      'import duckdb; print("DuckDB version:", duckdb.__version__)'; \
    retry_plugin_install \
      "GeoParquet Downloader (Overture, Source & Custom Cloud)"; \
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
    /usr/bin/python3 -c \
      'import duckdb; \
       version = tuple(int(part) for part in duckdb.__version__.split(".")[:2]); \
       assert version >= (1, 4), duckdb.__version__; \
       print("DuckDB version:", duckdb.__version__)'; \
    /usr/bin/python3 -c \
      'from qgis.core import Qgis; \
       assert Qgis.QGIS_VERSION.startswith("3.44."), Qgis.QGIS_VERSION; \
       print("QGIS version:", Qgis.QGIS_VERSION)'; \
    /usr/bin/python3 -c \
      'from qgis.core import QgsStacConnection; \
       print("QgsStacConnection available:", QgsStacConnection)'; \
    /usr/bin/python3 -c \
      'from osgeo import gdal; \
       print("GDAL version:", gdal.VersionInfo("--version")); \
       driver = gdal.GetDriverByName("Parquet"); \
       assert driver is not None, "GDAL Parquet driver unavailable"; \
       print("GDAL Parquet driver:", driver.ShortName)'; \
    /usr/bin/python3 -c \
      'from osgeo import gdal; \
       driver = gdal.GetDriverByName("FlatGeobuf"); \
       assert driver is not None, "GDAL FlatGeobuf driver unavailable"; \
       print("GDAL FlatGeobuf driver:", driver.ShortName)'; \
    if command -v ogrinfo >/dev/null 2>&1; then \
      ogrinfo --formats | grep -qi parquet; \
      echo "ogrinfo Parquet driver: available"; \
      ogrinfo --formats | grep -qi flatgeobuf; \
      echo "ogrinfo FlatGeobuf driver: available"; \
    fi; \
    QT_QPA_PLATFORM=offscreen \
      /usr/local/bin/qgis-launch --version; \
    qgis-plugin-manager --help; \
    test -d /opt/qgis/plugins

# ------------------------------------------------------------
# Optimization
# ------------------------------------------------------------
RUN set -eux; \
    ldconfig; \
    ldconfig -p | grep -F 'libarrow_dataset.so.1601'; \
    ldconfig -p | grep -F 'libparquet.so.1601'
# ------------------------------------------------------------
# Restore standard Jupyter working directory and user
# ------------------------------------------------------------
WORKDIR /home/${NB_USER}

USER ${NB_USER}
