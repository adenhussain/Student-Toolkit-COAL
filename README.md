# Student Toolkit

A Windows desktop application written in **32-bit x86 assembly language** (MASM) using the **Irvine32** library and the **Win32 API**. It helps FAST students plan their CGPA and their study time.

**COAL Lab (EL-2003), FAST-NUCES Karachi, Fall 2026**
Group BCS-3E-06: **Aden Hussain** (25K-0828, group leader) and **Javaria Ahmed Shaikh** (25K-0825)
Instructor: Abdullah Shaikh

## Features

- **Accounts with a PIN**: each student's data is saved in an encrypted file. The PIN is never stored, and a checksum detects any change made to the file outside the program.
- **Dashboard**: current CGPA, GPA needed for a target, next exam, study streak, GPA chart and today's plan.
- **Courses**: credits, marks, attendance (classes you can still skip), difficulty and preparation.
- **Grades**: CGPA from past semesters, GPA required for a target CGPA, grade sliders, marks needed in each final, and **Auto-solve** for the easiest grade combination.
- **Smart Planner**: a study timetable that reacts to exam dates (score = difficulty × credits × (6 − preparation) × urgency × risk), with a burnout warning.
- **Timer**: Pomodoro 25/5/15, always-on-top mini timer, **Focus Guard** (warns when YouTube, Instagram, etc. are open), streaks and 8 badges.
- **Deadlines**: quizzes, assignments, exams and labs, sorted by days left.
- **Files**: activity log, Excel (SpreadsheetML), CSV and timetable export.
- **Interface**: custom-drawn pastel GUI with 5 themes, tray icon and notifications, DPI aware.

All maths uses integer fixed-point arithmetic (GPA × 100, marks × 10); no floating point.

## How to build and run

Requirements: Windows 10/11, Visual Studio 2022 or 2026 with **Desktop development with C++** (includes MASM and the Windows SDK), and the **Irvine32** library in `C:\Irvine`.

1. Open `StudentToolkit.sln` in Visual Studio.
2. Select **Debug** and **x86**.
3. **Build > Build Solution**, then **Debug > Start Without Debugging** (Ctrl+F5).

The program is created as `bin\Debug\StudentToolkit.exe`. On first run, click **Create an account**. Data files are created in `bin\Debug\data\`.

## Source files

| Folder / file | Contents |
| --- | --- |
| `StudentToolkit/src/main.asm` | Entry point, message loop, main window, menu |
| `StudentToolkit/src/*.asm` | 28 modules: screens, dialogs, calculations, file handling, drawing |
| `StudentToolkit/include/app.inc` | Shared constants, structures and procedure prototypes |
| `StudentToolkit/include/win32gui.inc` | Win32 structures, constants and prototypes |
| `StudentToolkit/res/app.rc` | Icon, menu and keyboard shortcuts |

About 16,600 lines of assembly and 275 procedures.
