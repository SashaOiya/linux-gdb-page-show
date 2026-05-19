import gdb
import re

PAGE_SHIFT = 12
PAGE_SIZE = 1 << PAGE_SHIFT

_PAGE_VALID    = 1 << 0
_PAGE_READ     = 1 << 1
_PAGE_WRITE    = 1 << 2
_PAGE_EXEC     = 1 << 3
_PAGE_USER     = 1 << 4

PAGE_OFFSET_RISCV = 0xff60000000000000
DRAM_BASE_RISCV   = 0x80000000

class LxUserPageTables(gdb.Command):
    """Выводит дерево таблиц страниц пользовательского пространства для RISC-V (Sv39) через физическую память QEMU.
    Использование: lx-user-pt <PID>
    """

    def __init__(self):
        super(LxUserPageTables, self).__init__("lx-user-pt", gdb.COMMAND_DATA)

    def invoke(self, arg, from_tty):
        if not arg:
            print("Ошибка: Укажите PID. Пример: lx-user-pt 1")
            return

        try:
            target_pid = int(arg)
        except ValueError:
            print("Ошибка: PID должен быть числом.")
            return

        task_ptr = self.find_task_by_pid(target_pid)
        if not task_ptr:
            print(f"Процесс с PID {target_pid} не найден.")
            return

        comm = task_ptr['comm'].string()
        print(f"Построение дерева страниц для процесса: {comm} (PID: {target_pid})")

        mm_ptr = task_ptr['mm']
        if int(mm_ptr) == 0:
            print("Это поток ядра, у него нет пользовательских таблиц страниц.")
            return

        # QEMU: PA = VA - PAGE_OFFSET + DRAM_BASE
        pgd_virt_addr = int(mm_ptr['pgd'])
        pgd_phys_addr = pgd_virt_addr - PAGE_OFFSET_RISCV + DRAM_BASE_RISCV

        print(f"PGD (корень) Физический адрес: {hex(pgd_phys_addr)}")
        print("-" * 60)

        self.walk_level(pgd_phys_addr, level_name="PGD", depth=0)

    def find_task_by_pid(self, pid):
        try:
            task = gdb.parse_and_eval(f"pid_task(find_vpid({pid}), 0)")
            if int(task) != 0:
                return task
        except gdb.error:
            init_task = gdb.parse_and_eval("&init_task")
            curr = init_task
            while True:
                if int(curr['pid']) == pid:
                    return curr
                list_head = curr['tasks']
                next_node = list_head['next']
                offset = gdb.parse_and_eval("(unsigned long)&((struct task_struct *)0)->tasks")
                curr = gdb.Value(int(next_node) - int(offset)).cast(gdb.lookup_type("struct task_struct").pointer())
                if int(curr) == int(init_task):
                    break
        return None

    def entry_to_paddr(self, entry_val):
        ppn = (entry_val >> 10) & 0x3fffffffffffff
        return ppn << PAGE_SHIFT

    def read_phys_mem_qemu(self, phys_addr):
        """Читает 64 бита из ФИЗИЧЕСКОЙ памяти напрямую через монитор QEMU.
        """
        try:
            gdb_output = gdb.execute(f"monitor xp /1gx {hex(phys_addr)}", to_string=True)
            match = re.search(r":\s+(0x[0-9a-fA-F]+)", gdb_output)
            if match:
                return int(match.group(1), 16)
            return 0
        except gdb.error:
            return 0

    def walk_level(self, table_phys_addr, level_name, depth):
        indent = "    " * depth
        max_entries = 256 if level_name == "PGD" else 512

        for i in range(max_entries):
            entry_phys_addr = table_phys_addr + (i * 8)
            entry_val = self.read_phys_mem_qemu(entry_phys_addr)

            if entry_val & _PAGE_VALID:
                next_table_phys = self.entry_to_paddr(entry_val)
                is_leaf = bool(entry_val & (_PAGE_READ | _PAGE_WRITE | _PAGE_EXEC)) or (level_name == "PTE")

                if is_leaf:
                    w_flag = "W" if (entry_val & _PAGE_WRITE) else "-"
                    u_flag = "U" if (entry_val & _PAGE_USER) else "S"
                    x_flag = "X" if (entry_val & _PAGE_EXEC) else "-"
                    r_flag = "R" if (entry_val & _PAGE_READ) else "-"

                    lazy_suffix = ""
                    if not (entry_val & (_PAGE_READ | _PAGE_WRITE | _PAGE_EXEC)):
                        lazy_suffix = " [Lazy/CoW allocation]"
                        r_flag = "R"

                    if level_name == "PGD":
                        page_type = "Гига-страница (1 ГБ)"
                    elif level_name == "PMD":
                        page_type = "Мега-страница (2 МБ)"
                    else:
                        page_type = "Обычная страница (4 КБ)"

                    print(f"{indent}└── {level_name} [{i:03d}] -> Физическая RAM: {hex(next_table_phys)} [{u_flag}-{r_flag}{w_flag}{x_flag}]{lazy_suffix} ({page_type})")
                else:
                    if level_name == "PGD":
                        next_name = "PMD"
                    elif level_name == "PMD":
                        next_name = "PTE"
                    else:
                        next_name = "unknown"

                    if next_name != "unknown":
                        print(f"{indent}└── {level_name} [{i:03d}] -> Переход на {next_name} (Физический адрес таблицы: {hex(next_table_phys)})")
                        self.walk_level(next_table_phys, level_name=next_name, depth=depth+1)

LxUserPageTables()