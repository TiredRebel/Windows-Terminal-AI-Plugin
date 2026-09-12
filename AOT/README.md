# TerminalAI.Aot - Високопродуктивний бінарний модуль C# для PowerShell

Бінарний C# модуль для прискорення розширення TerminalAI:
- **Zero-Allocation Client:** Статичний `SocketsHttpHandler` з пулом Keep-Alive та HTTP/2 без перестворення TCP-з'єднань.
- **Обхід інтерпретатора:** Скомпільований код C# замість інтерпретації великих `.psm1` скриптів PowerShell.
- **Нативний Win32 Console:** Апаратні скан-коди для миттєвої вставки та беззатримкове зчитування клавіш без дублювання.
- **Повна функціональна сумісність:** Підтримка всіх підкоманд базової версії (`status`, `models`, `model`, `lang`, `config`), швидка довідка, пояснення команд (`-Explain`), режим запитань (`-Ask`) та повне інтерактивне меню.

## Збірка:
```powershell
dotnet build -c Release
```

## Використання:
```powershell
# Імпорт скомпільованого бінарного модуля
Import-Module ./AOT/bin/Release/net10.0/TerminalAI.Aot.dll

# Швидка довідка
ai-fast

# Генерація команди PowerShell
ai-fast "показати відкриті порти"

# Інформація про систему та статус
ai-fast status

# Список встановлених моделей Ollama
ai-fast models

# Зміна активної моделі
ai-fast model granite4.2:8b

# Перемикання мови інтерфейсу
ai-fast lang uk | en

# Перегляд поточної конфігурації
ai-fast config

# Генерація з детальним поясненням команди
ai-fast "архівувати папку logs" -Explain

# Текстова відповідь на запитання
ai-fast "що таке PowerShell pipeline?" -Ask
```

