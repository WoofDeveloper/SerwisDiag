// SerwisDiag - launcher EXE. Uruchamia SerwisDiag.ps1 (leżący obok pliku EXE) w Windows PowerShell bez okna konsoli.
// SerwisDiag.exe: manifest wymusza uprawnienia administratora (UAC). SerwisDiagMonitor.exe (kompilacja z MONITOR):
// monitorowanie w tle z uprawnieniami użytkownika, który go uruchomił - bez okna UAC przy logowaniu.
// Kompilacja: tools\Build-Exe.ps1 (kompilator C# 5 z .NET Framework 4.x).
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "SerwisDiag.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Nie znaleziono pliku SerwisDiag.ps1 obok programu.\nSkopiuj cały folder SerwisDiag (nie sam plik EXE).",
                "SerwisDiag", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        string sysRoot = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
        string ps = Path.Combine(sysRoot, @"System32\WindowsPowerShell\v1.0\powershell.exe");
        string sysnative = Path.Combine(sysRoot, @"Sysnative\WindowsPowerShell\v1.0\powershell.exe");
        // proces 32-bitowy w 64-bitowym systemie: natywny PowerShell jest pod aliasem Sysnative
        if (!Environment.Is64BitProcess && Environment.Is64BitOperatingSystem && File.Exists(sysnative)) ps = sysnative;
        if (!File.Exists(ps))
        {
            MessageBox.Show("Nie znaleziono Windows PowerShell (" + ps + ").", "SerwisDiag", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 3;
        }
        string arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"";
#if MONITOR
        arguments += " -Monitor";
#else
        foreach (string a in args) arguments += " \"" + a.Replace("\"", "\\\"") + "\"";
#endif
        ProcessStartInfo psi = new ProcessStartInfo(ps, arguments);
#if MONITOR
        // monitor działa godzinami: folder programu jako katalog roboczy blokowałby jego usunięcie przy odinstalowaniu
        psi.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
#else
        psi.WorkingDirectory = dir;
#endif
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        try { Process.Start(psi); }
        catch (Exception ex)
        {
            MessageBox.Show("Nie udało się uruchomić programu: " + ex.Message, "SerwisDiag", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 4;
        }
        return 0;
    }
}
