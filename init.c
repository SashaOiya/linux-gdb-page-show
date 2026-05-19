#include <stdio.h>
#include <unistd.h>

int main() {
  printf("\n=== ПРИВЕТ ИЗ USER SPACE! Мой PID = %d ===\n", getpid());

  // Бесконечный цикл, чтобы процесс не завершался,
  // и мы могли заморозить ядро через Ctrl+C в GDB
  while (1) {
    sleep(3600);
  }
  return 0;
}