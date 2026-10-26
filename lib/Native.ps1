# SerwisDiag - drobne funkcje natywne (C# kompilowany w locie przez Add-Type).
# Kod C# celowo w składni C# 5 (kompilator wbudowany w .NET Framework 4.x na Windows 8+).

$global:SdNativeSource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class SdNative
{
    [DllImport("kernel32.dll")]
    private static extern bool GetFirmwareType(out uint firmwareType);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, uint inSize, byte[] outBuf, uint outSize, out uint returned, IntPtr ov);

    // Dziennik zdrowia NVMe (Log Page 02h, 512 bajtow) przez IOCTL_STORAGE_QUERY_PROPERTY.
    // Dziala bez uprawnien administratora (uchwyt z dostepem 0). Zwraca null i kod bledu Win32 w razie niepowodzenia.
    public static byte[] NvmeHealthLog(int disk, out int error)
    {
        error = 0;
        using (SafeFileHandle h = CreateFile(@"\\.\PhysicalDrive" + disk, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) { error = Marshal.GetLastWin32Error(); return null; }
            byte[] inb = new byte[8 + 40];
            BitConverter.GetBytes((uint)50).CopyTo(inb, 0);    // StorageDeviceProtocolSpecificProperty
            BitConverter.GetBytes((uint)0).CopyTo(inb, 4);     // PropertyStandardQuery
            BitConverter.GetBytes((uint)3).CopyTo(inb, 8);     // ProtocolTypeNvme
            BitConverter.GetBytes((uint)2).CopyTo(inb, 12);    // NVMeDataTypeLogPage
            BitConverter.GetBytes((uint)2).CopyTo(inb, 16);    // NVME_LOG_PAGE_HEALTH_INFO
            BitConverter.GetBytes((uint)0).CopyTo(inb, 20);    // sub value
            BitConverter.GetBytes((uint)40).CopyTo(inb, 24);   // ProtocolDataOffset
            BitConverter.GetBytes((uint)512).CopyTo(inb, 28);  // ProtocolDataLength
            byte[] outb = new byte[8 + 40 + 512];
            uint ret;
            if (!DeviceIoControl(h, 0x002D1400, inb, (uint)inb.Length, outb, (uint)outb.Length, out ret, IntPtr.Zero))
            {
                error = Marshal.GetLastWin32Error();
                return null;
            }
            uint off = BitConverter.ToUInt32(outb, 8 + 16);
            if (off + 8 + 512 > outb.Length) { error = 87; return null; }
            byte[] log = new byte[512];
            Array.Copy(outb, (int)(8 + off), log, 0, 512);
            return log;
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint QueryDosDevice(string deviceName, System.Text.StringBuilder target, uint max);

    // "C:" -> "\Device\HarddiskVolume3"; pusty napis, gdy litera nie istnieje
    public static string DosDevice(string letter)
    {
        System.Text.StringBuilder sb = new System.Text.StringBuilder(1024);
        try { if (QueryDosDevice(letter, sb, (uint)sb.Capacity) == 0) return ""; }
        catch (Exception) { return ""; }
        return sb.ToString();
    }

    // 1 = BIOS (Legacy), 2 = UEFI, 0 = nie udalo sie ustalic
    public static int FirmwareType()
    {
        try { uint t; if (GetFirmwareType(out t)) return (int)t; }
        catch (Exception) { }
        return 0;
    }

    // Rozmiar katalogu (bajty) i liczba plikow; ignoruje punkty reparse i niedostepne katalogi.
    public static long DirSize(string path, out long files)
    {
        files = 0;
        long total = 0;
        try { Walk(new DirectoryInfo(path), ref total, ref files, 0); }
        catch (Exception) { }
        return total;
    }

    private static void Walk(DirectoryInfo dir, ref long total, ref long files, int depth)
    {
        if (depth > 40) return;
        FileInfo[] fs = null;
        try { fs = dir.GetFiles(); } catch (Exception) { }
        if (fs != null)
        {
            foreach (FileInfo f in fs)
            {
                try { total += f.Length; files++; } catch (Exception) { }
            }
        }
        DirectoryInfo[] ds = null;
        try { ds = dir.GetDirectories(); } catch (Exception) { }
        if (ds != null)
        {
            foreach (DirectoryInfo d in ds)
            {
                try { if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue; }
                catch (Exception) { continue; }
                Walk(d, ref total, ref files, depth + 1);
            }
        }
    }
}

// Silnie typowane obiekty dla interfejsu WPF (wiazanie danych z PSCustomObject bywa zawodne).
public class SdUiRow
{
    public string Status { get; set; }
    public string StatusLabel { get; set; }
    public string Title { get; set; }
    public string Value { get; set; }
    public string Details { get; set; }
    public string Advice { get; set; }
    public string Category { get; set; }
    public string CategoryLabel { get; set; }
    public string Tag { get; set; }
}

public class SdNavItem : System.ComponentModel.INotifyPropertyChanged
{
    public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
    private string label = "";
    private string badge = "";
    private string dot = "#D0D5DD";
    public string Key { get; set; }
    public string Label { get { return label; } set { label = value; Notify("Label"); } }
    public string Badge { get { return badge; } set { badge = value; Notify("Badge"); } }
    public string Dot { get { return dot; } set { dot = value; Notify("Dot"); } }
    private void Notify(string name)
    {
        System.ComponentModel.PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new System.ComponentModel.PropertyChangedEventArgs(name));
    }
}

// Liczniki wydajnosci przez PDH z nazwami angielskimi (PdhAddEnglishCounter) - niezalezne od jezyka systemu.
public sealed class SdPdh : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    private struct PdhValue { public uint CStatus; public uint Pad; public double Value; }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhOpenQuery(string source, IntPtr user, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
    [DllImport("pdh.dll")]
    private static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll")]
    private static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, out uint type, out PdhValue value);
    [DllImport("pdh.dll")]
    private static extern uint PdhCloseQuery(IntPtr query);

    private IntPtr query = IntPtr.Zero;
    private System.Collections.Generic.List<IntPtr> counters = new System.Collections.Generic.List<IntPtr>();

    public SdPdh()
    {
        uint r = PdhOpenQuery(null, IntPtr.Zero, out query);
        if (r != 0) throw new InvalidOperationException("PdhOpenQuery 0x" + r.ToString("X"));
    }

    // Zwraca indeks licznika albo -1, gdy licznik nie istnieje (np. uszkodzone liczniki wydajnosci).
    public int Add(string englishPath)
    {
        IntPtr c;
        uint r = PdhAddEnglishCounter(query, englishPath, IntPtr.Zero, out c);
        if (r != 0) return -1;
        counters.Add(c);
        return counters.Count - 1;
    }

    public bool Collect() { return PdhCollectQueryData(query) == 0; }

    // PDH_FMT_DOUBLE | PDH_FMT_NOCAP100; NaN przy bledzie
    public double Get(int index)
    {
        if (index < 0 || index >= counters.Count) return double.NaN;
        uint type; PdhValue v;
        uint r = PdhGetFormattedCounterValue(counters[index], 0x00008200, out type, out v);
        if (r != 0 || v.CStatus != 0) return double.NaN;
        return v.Value;
    }

    public void Dispose()
    {
        if (query != IntPtr.Zero) { PdhCloseQuery(query); query = IntPtr.Zero; }
    }
}
'@

function Initialize-SdNative {
    # Typ jest widoczny we wszystkich runspace'ach procesu, więc kompilujemy tylko raz.
    if ('SdNative' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $global:SdNativeSource -Language CSharp -ErrorAction Stop
        return $true
    } catch {
        Write-SdLog ('Kompilacja SdNative: ' + $_.Exception.Message) 'WARN'
        return $false
    }
}

function New-SdPdh {
    # Zwraca obiekt SdPdh albo $null, gdy PDH jest niedostępne. Po użyciu wywołaj .Dispose().
    if (-not (Initialize-SdNative)) { return $null }
    try { return (New-Object SdPdh) } catch { Write-SdLog ('PDH: ' + $_.Exception.Message) 'WARN'; return $null }
}

function Get-SdDirSize {
    # Zwraca @{ Bytes; Files }. Gdy kompilacja natywna się nie powiodła - wolniejsza wersja w PowerShell.
    param([Parameter(Mandatory = $true)][string]$Path)
    $res = [pscustomobject]@{ Bytes = [int64]0; Files = [int64]0 }
    if (-not (Test-Path -LiteralPath $Path)) { return $res }
    if (Initialize-SdNative) {
        $files = [int64]0
        $res.Bytes = [SdNative]::DirSize($Path, [ref]$files)
        $res.Files = $files
        return $res
    }
    try {
        $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        $m = $items | Measure-Object -Property Length -Sum
        $res.Files = [int64]$m.Count
        if ($m.Sum) { $res.Bytes = [int64]$m.Sum }
    } catch { }
    return $res
}
