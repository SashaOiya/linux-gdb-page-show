#!/bin/bash
set -e

# Версии
KERNEL_VER="v6.8"
OPENSBI_VER="v1.2"
ROOT_DIR=$(pwd)

echo "--- Проверка зависимостей ---"
PACKAGES=""
if ! command -v qemu-system-riscv64 &> /dev/null; then
    echo "qemu-system-riscv64 не найден."
    PACKAGES="$PACKAGES qemu-system-misc"
fi

if ! command -v riscv64-linux-gnu-gcc &> /dev/null; then
    echo "riscv64-linux-gnu-gcc не найден."
    PACKAGES="$PACKAGES gcc-riscv64-linux-gnu"
fi

if [ ! -z "$PACKAGES" ]; then
    echo "Для работы необходимо установить пакеты:"
    echo "sudo apt update && sudo apt install $PACKAGES"
    exit 1
fi
echo "Все инструменты установлены."

echo "--- Настройка окружения ---"

# Клонируем OpenSBI
if [ ! -d "opensbi" ]; then
    echo "Клонирование OpenSBI ($OPENSBI_VER)..."
    git clone --depth 1 --branch $OPENSBI_VER https://github.com/riscv-software-src/opensbi.git opensbi
fi

# Клонируем Linux
if [ ! -d "linux" ]; then
    echo "Клонирование Linux Kernel ($KERNEL_VER)..."
    git clone --depth 1 --branch $KERNEL_VER https://github.com/torvalds/linux.git linux
fi

sudo apt update && sudo apt install -y gdb-multiarch libncurses-dev bison flex libssl-dev libelf-dev bc

echo "--- Конфигурация завершена ---"

ARCH=riscv
CROSS_COMPILE=riscv64-linux-gnu-

echo "--- Сборка OpenSBI ---"
cd opensbi
make CROSS_COMPILE=$CROSS_COMPILE PLATFORM=generic -j$(nproc)
cd ..

echo "--- Сборка ядра Linux ---"
cd linux
if [ ! -f .config ]; then
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig
fi

# Включаем отладочную информацию прямо в .config
echo "--- Включение отладочных символов (CONFIG_DEBUG_INFO) ---"
./scripts/config --enable CONFIG_DEBUG_INFO
./scripts/config --enable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
./scripts/config --enable CONFIG_DEBUG_KERNEL
./scripts/config --enable CONFIG_GDB_SCRIPTS

# Обновляем конфигурацию на основе измененных флагов
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE olddefconfig

# Собираем и сам Image, и полноценный vmlinux с символами (-j$(nproc) задействует все ядра CPU)
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)
cd ..

echo "Сборка всех компонентов завершена."