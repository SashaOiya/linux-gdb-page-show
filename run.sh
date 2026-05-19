#!/bin/bash
# Убрали set -e, чтобы падение одной команды (например, kill) не ломало весь скрипт

ROOT_DIR=$(pwd)
GDB_SCRIPT_NAME="linux_gdb_page_show.py"

VMLINUX="$ROOT_DIR/linux/vmlinux"
IMAGE="$ROOT_DIR/linux/arch/riscv/boot/Image"
FW_DYNAMIC="$ROOT_DIR/opensbi/build/platform/generic/firmware/fw_dynamic.bin"

echo "--- Проверка наличия необходимых файлов ---"
if [ ! -f "$VMLINUX" ]; then
    echo "Ошибка: Не найден файл отладочных символов ядра: $VMLINUX"
    exit 1
fi

if [ ! -f "$ROOT_DIR/$GDB_SCRIPT_NAME" ]; then
    echo "Ошибка: Python-скрипт $GDB_SCRIPT_NAME не найден."
    exit 1
fi

echo "--- Создание конфигурации для автозапуска GDB ---"
GDB_INIT_FILE=$(mktemp)
cat << EOF > "$GDB_INIT_FILE"
target remote :1234
source $ROOT_DIR/$GDB_SCRIPT_NAME
echo \n--- [GDB] Скрипт $GDB_SCRIPT_NAME успешно загружен! ---\n
echo --- [GDB] Доступна команда: lx-user-pt <PID> ---\n
echo --- [GDB] Для продолжения загрузки ядра введите 'continue' или 'c' ---\n
EOF

echo "--- Запуск Linux в QEMU (в фоновом режиме) ---"
# Запускаем QEMU в отдельной сессии процесса (setsid), 
# чтобы он полностью игнорировал Ctrl+C, нажатый в этом терминале!
setsid qemu-system-riscv64 -M virt -m 2G -smp 2 \
    -bios "$FW_DYNAMIC" \
    -kernel "$IMAGE" \
    -initrd "$ROOT_DIR/initramfs.cpio.gz" \
    -nographic \
    -s -S > qemu.log 2>&1 &

QEMU_PID=$!

# Функция очистки: сработает ТОЛЬКО когда мы сами закроем GDB
cleanup() {
    echo -e "\n--- [Скрипт] Завершение работы QEMU (PID: $QEMU_PID) ---"
    kill $QEMU_PID 2>/dev/null || true
    rm -f "$GDB_INIT_FILE"
}
# Ловим только нормальный выход из скрипта (когда закроется GDB)
trap cleanup EXIT

echo "Ожидание инициализации QEMU..."
sleep 1

echo "--- Запуск кросс-платформенного GDB ---"
if command -v riscv64-linux-gnu-gdb &> /dev/null; then
    riscv64-linux-gnu-gdb "$VMLINUX" -x "$GDB_INIT_FILE"
elif command -v gdb-multiarch &> /dev/null; then
    gdb-multiarch "$VMLINUX" -x "$GDB_INIT_FILE"
else
    echo "Ошибка: gdb не найден."
    exit 1
fi