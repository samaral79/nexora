# Configuração comum do build da Nexora Linux (fazer `source` disto)
export DISTRO_NAME="Nexora Linux"
export DISTRO_ID=nexora
export LFS_VERSION=13.1
export LFS=/mnt/lfs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PROJ=/home/samaral79/Projects/lfs
export IMG=$PROJ/lfs.img
export IMG_SIZE=60G
export MAKEFLAGS=-j$(nproc)
