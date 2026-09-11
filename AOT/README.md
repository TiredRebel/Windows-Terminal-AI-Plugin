# TerminalAI.Aot - Високопродуктивний бінарний модуль C# для PowerShell

Бінарний C# модуль для прискорення розширення TerminalAI:
- **Zero-Allocation Client:** Статичний `SocketsHttpHandler` з пулом Keep-Alive та HTTP/2 без перестворення TCP-з'єднань.
- **Обхід інтерпретатора:** Скомпільований код замість інтерпретації `.psm1` скриптів PowerShell.
- **Нативний Win32 Console:** Апаратні скан-коди для миттєвої вставки та беззатримкове зчитування клавіш.

## Збірка та використання:
```powershell
# Збірка модуля у режимі Release
dotnet build -c Release

# Імпорт скомпільованого бінарного модуля
Import-Module ./bin/Release/net10.0/TerminalAI.Aot.dll

# Використання швидкої команди
ai-fast "показати відкриті порти"
```
