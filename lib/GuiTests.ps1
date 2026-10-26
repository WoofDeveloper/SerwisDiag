# SerwisDiag - proste testy sprzętowe w oknach WPF: test ekranu (martwe piksele) i test klawiatury.

$global:SdScreenTestXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Test ekranu" WindowStyle="None" WindowState="Maximized" Topmost="True" ResizeMode="NoResize"
        Background="White" ShowInTaskbar="False" Cursor="None" FontFamily="Segoe UI">
  <Grid>
    <Border x:Name="HintBox" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,48" Padding="20,10" CornerRadius="10" Background="#C8000000">
      <TextBlock x:Name="HintText" Foreground="White" FontSize="16"/>
    </Border>
  </Grid>
</Window>
'@

$global:SdKeyboardTestXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Test klawiatury" Width="1180" Height="600" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <DockPanel Margin="18">
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,12">
      <Button x:Name="KbReset" DockPanel.Dock="Right" Content="Wyczyść" Padding="14,6" Focusable="False"/>
      <TextBlock x:Name="KbInfo" FontSize="14" VerticalAlignment="Center"/>
    </DockPanel>
    <Border Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1" Padding="18">
      <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
        <StackPanel x:Name="KbPanel"/>
      </ScrollViewer>
    </Border>
  </DockPanel>
</Window>
'@

function Show-SdScreenTest {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$global:SdScreenTestXaml)
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($global:SdUi -and $global:SdUi.Window) { $w.Owner = $global:SdUi.Window }
    $hint = $w.FindName('HintText')
    $hintBox = $w.FindName('HintBox')
    $colors = @('#FFFFFF', '#000000', '#FF0000', '#00FF00', '#0000FF', '#808080', '#FFFF00', '#00FFFF', '#FF00FF')
    $names = @('biały', 'czarny', 'czerwony', 'zielony', 'niebieski', 'szary', 'żółty', 'cyjan', 'magenta', 'gradient (pasma)')
    $state = @{ I = 0 }
    $apply = {
        $i = $state.I
        if ($i -lt $colors.Count) {
            $w.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($colors[$i])
        } else {
            $g = New-Object System.Windows.Media.LinearGradientBrush
            $g.StartPoint = New-Object System.Windows.Point(0, 0); $g.EndPoint = New-Object System.Windows.Point(1, 0)
            [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::Black, 0)))
            [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White, 1)))
            $w.Background = $g
        }
        $hint.Text = ('{0}/{1}: {2}   |   klik, spacja lub strzałka w prawo - następny kolor   |   strzałka w lewo - poprzedni   |   Esc - zakończ' -f ($i + 1), ($colors.Count + 1), $names[$i])
    }.GetNewClosure()
    $next = {
        $state.I = ($state.I + 1) % ($colors.Count + 1)
        & $apply
        $hintBox.Visibility = 'Collapsed'
    }.GetNewClosure()
    $prev = {
        $state.I = ($state.I - 1 + $colors.Count + 1) % ($colors.Count + 1)
        & $apply
        $hintBox.Visibility = 'Collapsed'
    }.GetNewClosure()
    $w.Add_MouseLeftButtonDown({ & $next }.GetNewClosure())
    $w.Add_KeyDown({
            param($s, $e)
            switch ([string]$e.Key) {
                'Escape' { $w.Close() }
                'Right' { & $next }
                'Space' { & $next }
                'Return' { & $next }
                'Left' { & $prev }
            }
        }.GetNewClosure())
    & $apply
    if ($global:SdUi) { $global:SdUi.TestWindow = $w }
    [void]$w.ShowDialog()
}

function Show-SdKeyboardTest {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$global:SdKeyboardTestXaml)
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($global:SdUi -and $global:SdUi.Window) { $w.Owner = $global:SdUi.Window }
    Set-SdUiWindowFit $w
    $panel = $w.FindName('KbPanel')
    $info = $w.FindName('KbInfo')
    $reset = $w.FindName('KbReset')

    # każdy wiersz: lista @(etykieta, nazwa klawisza WPF, szerokość względna); pusta nazwa = odstęp
    $rows = @(
        , @(@('Esc', 'Escape', 1.3), @('', '', 0.6), @('F1', 'F1', 1), @('F2', 'F2', 1), @('F3', 'F3', 1), @('F4', 'F4', 1), @('', '', 0.3), @('F5', 'F5', 1), @('F6', 'F6', 1), @('F7', 'F7', 1), @('F8', 'F8', 1), @('', '', 0.3), @('F9', 'F9', 1), @('F10', 'F10', 1), @('F11', 'F11', 1), @('F12', 'F12', 1), @('', '', 0.3), @('PrtSc', 'Snapshot', 1.1), @('ScrLk', 'Scroll', 1.1), @('Pause', 'Pause', 1.1))
        , @(@('`', 'OemTilde', 1), @('1', 'D1', 1), @('2', 'D2', 1), @('3', 'D3', 1), @('4', 'D4', 1), @('5', 'D5', 1), @('6', 'D6', 1), @('7', 'D7', 1), @('8', 'D8', 1), @('9', 'D9', 1), @('0', 'D0', 1), @('-', 'OemMinus', 1), @('=', 'OemPlus', 1), @('Backspace', 'Back', 2.1), @('', '', 0.3), @('Ins', 'Insert', 1.1), @('Home', 'Home', 1.1), @('PgUp', 'Prior', 1.1))
        , @(@('Tab', 'Tab', 1.5), @('Q', 'Q', 1), @('W', 'W', 1), @('E', 'E', 1), @('R', 'R', 1), @('T', 'T', 1), @('Y', 'Y', 1), @('U', 'U', 1), @('I', 'I', 1), @('O', 'O', 1), @('P', 'P', 1), @('[', 'OemOpenBrackets', 1), @(']', 'OemCloseBrackets', 1), @('\', 'OemPipe', 1.6), @('', '', 0.3), @('Del', 'Delete', 1.1), @('End', 'End', 1.1), @('PgDn', 'Next', 1.1))
        , @(@('Caps', 'Capital', 1.8), @('A', 'A', 1), @('S', 'S', 1), @('D', 'D', 1), @('F', 'F', 1), @('G', 'G', 1), @('H', 'H', 1), @('J', 'J', 1), @('K', 'K', 1), @('L', 'L', 1), @(';', 'OemSemicolon', 1), @("'", 'OemQuotes', 1), @('Enter', 'Return', 2.3))
        , @(@('Shift', 'LeftShift', 2.3), @('Z', 'Z', 1), @('X', 'X', 1), @('C', 'C', 1), @('V', 'V', 1), @('B', 'B', 1), @('N', 'N', 1), @('M', 'M', 1), @(',', 'OemComma', 1), @('.', 'OemPeriod', 1), @('/', 'OemQuestion', 1), @('Shift', 'RightShift', 2.8), @('', '', 1.4), @('↑', 'Up', 1.1))
        , @(@('Ctrl', 'LeftCtrl', 1.4), @('Win', 'LWin', 1.3), @('Alt', 'LeftAlt', 1.3), @('Spacja', 'Space', 6.1), @('Alt', 'RightAlt', 1.3), @('Win', 'RWin', 1.3), @('Menu', 'Apps', 1.3), @('Ctrl', 'RightCtrl', 1.4), @('', '', 0.3), @('←', 'Left', 1.1), @('↓', 'Down', 1.1), @('→', 'Right', 1.1))
        , @(@('Num', 'NumLock', 1.1), @('/', 'Divide', 1), @('*', 'Multiply', 1), @('-', 'Subtract', 1), @('', '', 0.4), @('7', 'NumPad7', 1), @('8', 'NumPad8', 1), @('9', 'NumPad9', 1), @('+', 'Add', 1), @('', '', 0.4), @('4', 'NumPad4', 1), @('5', 'NumPad5', 1), @('6', 'NumPad6', 1), @('', '', 0.4), @('1', 'NumPad1', 1), @('2', 'NumPad2', 1), @('3', 'NumPad3', 1), @('', '', 0.4), @('0', 'NumPad0', 1.6), @('.', 'Decimal', 1))
    )
    $conv = New-Object System.Windows.Media.BrushConverter
    $map = @{}
    $unit = 46.0
    foreach ($row in $rows) {
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'
        $sp.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
        foreach ($k in $row) {
            $b = New-Object System.Windows.Controls.Border
            $b.Width = [math]::Round($unit * [double]$k[2] + ([double]$k[2] - 1) * 4)
            $b.Height = 42
            $b.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
            if ($k[1]) {
                $b.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $b.BorderThickness = New-Object System.Windows.Thickness(1)
                $b.BorderBrush = $conv.ConvertFromString('#D0D5DD')
                $b.Background = $conv.ConvertFromString('#FFFFFF')
                $t = New-Object System.Windows.Controls.TextBlock
                $t.Text = $k[0]; $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'; $t.FontSize = 12.5
                $b.Child = $t
                $map[[string]$k[1]] = $b
            }
            [void]$sp.Children.Add($b)
        }
        [void]$panel.Children.Add($sp)
    }
    $state = @{ Pressed = @{}; Last = '' }
    $update = {
        $info.Text = ('Naciśnięto {0} z {1} klawiszy. Wciskaj kolejne klawisze - zadziałający zmieni kolor na zielony.{2}' -f $state.Pressed.Count, $map.Count, $(if ($state.Last) { '   Ostatni: ' + $state.Last } else { '' }))
    }.GetNewClosure()
    $w.Add_PreviewKeyDown({
            param($s, $e)
            $k = $e.Key
            if ($k -eq [System.Windows.Input.Key]::System) { $k = $e.SystemKey }
            if ($k -eq [System.Windows.Input.Key]::ImeProcessed) { $k = $e.ImeProcessedKey }
            $name = [string]$k
            $state.Last = $name
            if ($map.ContainsKey($name)) {
                $map[$name].Background = $conv.ConvertFromString('#B7EBC6')
                $map[$name].BorderBrush = $conv.ConvertFromString('#12B76A')
                $state.Pressed[$name] = $true
            }
            & $update
            $e.Handled = $true
        }.GetNewClosure())
    $reset.Add_Click({
            foreach ($key in @($map.Keys)) { $map[$key].Background = $conv.ConvertFromString('#FFFFFF'); $map[$key].BorderBrush = $conv.ConvertFromString('#D0D5DD') }
            $state.Pressed.Clear(); $state.Last = ''
            & $update
        }.GetNewClosure())
    & $update
    if ($global:SdUi) { $global:SdUi.TestWindow = $w }
    [void]$w.ShowDialog()
}
