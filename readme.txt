STUDENT TOOLKIT  -  COAL Lab (EL-2003) Final Project, Fall 2026
Group BCS-3E-06: Aden Hussain (25K-0828, leader), Javaria Ahmed Shaikh (25K-0825)
Instructor: Abdullah Shaikh

A Win32 GUI program written in 32-bit x86 assembly (MASM) with Irvine32:
CGPA target planner, smart study planner, Pomodoro timer with Focus Guard,
deadlines, encrypted save files, activity log and Excel/CSV/timetable export.


WHAT YOU NEED
  - Windows 10 or 11
  - Visual Studio 2022 or 2026 with "Desktop development with C++"
    (this installs MASM, ml.exe, and the Windows SDK)
  - The Irvine32 library installed in C:\Irvine
    (C:\Irvine\Irvine32.inc and C:\Irvine\Irvine32.lib must exist)


HOW TO ASSEMBLE AND RUN
  1. Unzip everything, keeping the folders.
  2. Double-click StudentToolkit.sln to open it in Visual Studio.
  3. At the top, choose the configuration "Debug" and the platform "x86".
  4. Build > Build Solution   (Ctrl+Shift+B)
  5. Debug > Start Without Debugging   (Ctrl+F5)
  The program is created as bin\Debug\StudentToolkit.exe.

  If Visual Studio asks to "retarget" the project (older version of
  Visual Studio), click OK.
  If Irvine32 is installed somewhere else, change C:\Irvine in
  Project > Properties > Microsoft Macro Assembler > General > Include Paths
  and in Linker > Input > Additional Dependencies.


FIRST USE
  - On the login window click "Create an account", enter a name, a
    username and a 4-6 digit PIN.
  - Your data is saved, encrypted, in bin\Debug\data\<username>.dat and
    every action is logged in bin\Debug\data\<username>.log. These files
    are created by the program; no data file is needed to start.
  - Help > Help (F1) explains every screen.
  - On the Timer screen, "Demo speed" runs a 25-minute session in about
    2 minutes for demonstrations.


FILES
  StudentToolkit.sln                    Visual Studio solution
  StudentToolkit\StudentToolkit.vcxproj project (MASM build, linker settings)
  StudentToolkit\include\app.inc        shared constants, structures, PROTOs
  StudentToolkit\include\win32gui.inc   Win32 structures, constants, PROTOs
  StudentToolkit\src\*.asm              28 source files (main.asm = entry)
  StudentToolkit\res\app.rc, app.ico    icon, menu, shortcuts, version info
