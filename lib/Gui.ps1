# SerwisDiag - interfejs graficzny (WPF)
# Wymaga STA - powershell.exe od wersji 3.0 domyślnie działa w STA. Skanowanie działa w osobnym runspace,
# dzięki czemu okno pozostaje responsywne; wyniki spływają do okna przez współdzielony kontekst.

$global:SdUiXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SerwisDiag - diagnostyka systemu Windows" Width="1260" Height="840" MinWidth="1040" MinHeight="680"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9"
        UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#D0D5DD"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#1B2433"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#EEF4FB"/><Setter TargetName="bd" Property="BorderBrush" Value="#0F6CBD"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#DCE9F8"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Padding" Value="18,8"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#0F6CBD" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#0B5A9E"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#094A82"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="7,5"/>
      <Setter Property="BorderBrush" Value="#D0D5DD"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Margin" Value="0,1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="bd" CornerRadius="8" Background="Transparent" Padding="10,7">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#F2F4F7"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="Background" Value="#E0EAFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BadgeBorder" TargetType="Border">
      <Setter Property="CornerRadius" Value="5"/>
      <Setter Property="Padding" Value="8,2"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Background" Value="#EAECF0"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding Status}" Value="crit"><Setter Property="Background" Value="#FEE4E2"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="warn"><Setter Property="Background" Value="#FEF0C7"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="ok"><Setter Property="Background" Value="#D1FADF"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="info"><Setter Property="Background" Value="#E0EAFF"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="error"><Setter Property="Background" Value="#EBE9FE"/></DataTrigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="BadgeText" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="#475467"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding Status}" Value="crit"><Setter Property="Foreground" Value="#B42318"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="warn"><Setter Property="Foreground" Value="#93370D"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="ok"><Setter Property="Foreground" Value="#067647"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="info"><Setter Property="Foreground" Value="#175CD3"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="error"><Setter Property="Foreground" Value="#6941C6"/></DataTrigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="BarBorder" TargetType="Border">
      <Setter Property="Background" Value="#98A2B3"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding Status}" Value="crit"><Setter Property="Background" Value="#D92D20"/></DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="warn"><Setter Property="Background" Value="#F79009"/></DataTrigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="WrapText" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="6,5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#F7F8FA"/>
      <Setter Property="Foreground" Value="#475467"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="BorderBrush" Value="#E4E7EC"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#EEF0F3"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="RowHeaderWidth" Value="0"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="SelectionMode" Value="Single"/>
      <Setter Property="RowBackground" Value="White"/>
      <Setter Property="AlternatingRowBackground" Value="#FBFCFD"/>
      <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
      <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
      <Setter Property="Foreground" Value="#1B2433"/>
      <Style.Resources>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#EAF2FB"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#1B2433"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#EAF2FB"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#1B2433"/>
      </Style.Resources>
    </Style>
    <DataTemplate x:Key="IssueCard">
      <Border CornerRadius="9" BorderThickness="1" BorderBrush="#E4E7EC" Background="White" Margin="0,0,0,10">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="7"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Grid.Column="0" CornerRadius="9,0,0,9" Style="{StaticResource BarBorder}"/>
          <StackPanel Grid.Column="1" Margin="14,10,14,12">
            <DockPanel>
              <Border DockPanel.Dock="Left" Style="{StaticResource BadgeBorder}" Margin="0,0,10,0">
                <TextBlock Text="{Binding StatusLabel}" Style="{StaticResource BadgeText}"/>
              </Border>
              <TextBlock DockPanel.Dock="Right" Text="{Binding CategoryLabel}" Foreground="#667085" FontSize="12" VerticalAlignment="Center" Margin="10,0,0,0"/>
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="14" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </DockPanel>
            <TextBlock Text="{Binding Value}" Foreground="#475467" TextWrapping="Wrap" Margin="0,5,0,0"/>
            <Border Background="#F4F8FF" BorderBrush="#D6E4FF" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,8,0,0">
              <Border.Style>
                <Style TargetType="Border">
                  <Style.Triggers><DataTrigger Binding="{Binding Advice}" Value=""><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers>
                </Style>
              </Border.Style>
              <TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Zalecenie: "/><Run Text="{Binding Advice, Mode=OneWay}"/></TextBlock>
            </Border>
          </StackPanel>
        </Grid>
      </Border>
    </DataTemplate>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- nagłówek -->
    <Border x:Name="HeaderBorder" Grid.Row="0" Padding="22,14">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#0A3A66" Offset="0"/>
          <GradientStop Color="#0F6CBD" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Border CornerRadius="12" Padding="11,4" Margin="0,0,8,0" Background="#26FFFFFF"><TextBlock x:Name="OsChipText" Foreground="White" FontSize="12"/></Border>
          <Border x:Name="AdminChip" CornerRadius="12" Padding="11,4" Margin="0,0,12,0" Background="#26FFFFFF"><TextBlock x:Name="AdminChipText" Foreground="White" FontSize="12" FontWeight="SemiBold"/></Border>
          <Button x:Name="BtnAbout" Content="O programie" Margin="0,0,8,0" Padding="12,5"/>
          <Button x:Name="BtnSettings" Content="Ustawienia" Margin="0" Padding="12,5"/>
        </StackPanel>
        <StackPanel>
          <TextBlock Text="SerwisDiag" FontSize="23" FontWeight="SemiBold" Foreground="White"/>
          <TextBlock x:Name="ShopText" Foreground="#CFE3F7" FontSize="12.5" Margin="0,1,0,0"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- banery: brak uprawnień administratora, nieaktualna baza wiedzy -->
    <StackPanel Grid.Row="1">
      <Border x:Name="AdminBanner" Background="#FEF0C7" BorderBrush="#F5D58B" BorderThickness="0,0,0,1" Padding="22,8" Visibility="Collapsed">
        <DockPanel>
          <Button x:Name="BtnElevate" DockPanel.Dock="Right" Content="Uruchom jako administrator" Padding="12,4" Margin="14,0,0,0"/>
          <TextBlock VerticalAlignment="Center" Foreground="#7A2E0E" TextWrapping="Wrap"
                     Text="Program działa bez uprawnień administratora - zostaną pominięte m.in. odczyt SMART dysków SATA/HDD, BitLocker, dzienniki zabezpieczeń, DISM i część napraw."/>
        </DockPanel>
      </Border>
      <Border x:Name="KbBanner" Background="#FEF0C7" BorderBrush="#F5D58B" BorderThickness="0,0,0,1" Padding="22,8" Visibility="Collapsed">
        <DockPanel>
          <Button x:Name="BtnKbAbout" DockPanel.Dock="Right" Content="Sprawdź nową wersję" Padding="12,4" Margin="14,0,0,0"/>
          <TextBlock x:Name="KbBannerText" VerticalAlignment="Center" Foreground="#7A2E0E" TextWrapping="Wrap"/>
        </DockPanel>
      </Border>
      <Border x:Name="UpdBanner" Background="#E0EAFF" BorderBrush="#B2CCFF" BorderThickness="0,0,0,1" Padding="22,8" Visibility="Collapsed">
        <DockPanel>
          <Button x:Name="BtnUpdate" DockPanel.Dock="Right" Content="Zaktualizuj" Padding="12,4" Margin="8,0,0,0"/>
          <Button x:Name="BtnUpdNotes" DockPanel.Dock="Right" Content="Co nowego" Padding="12,4" Margin="14,0,0,0"/>
          <TextBlock x:Name="UpdBannerText" VerticalAlignment="Center" Foreground="#1849A9" TextWrapping="Wrap"/>
        </DockPanel>
      </Border>
    </StackPanel>

    <!-- dane zlecenia i sterowanie -->
    <Border Grid.Row="2" Background="White" BorderBrush="#E4E7EC" BorderThickness="0,0,0,1" Padding="22,12">
      <StackPanel>
        <Grid x:Name="CtlGrid">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="130"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="190"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Zlecenie" VerticalAlignment="Center" Foreground="#667085" Margin="0,0,8,0"/>
          <TextBox x:Name="TxtTicket" Grid.Column="1"/>
          <TextBlock Grid.Column="2" Text="Klient" VerticalAlignment="Center" Foreground="#667085" Margin="16,0,8,0"/>
          <TextBox x:Name="TxtCustomer" Grid.Column="3"/>
          <TextBlock Grid.Column="4" Text="Zgłoszenie" VerticalAlignment="Center" Foreground="#667085" Margin="16,0,8,0"/>
          <TextBox x:Name="TxtNote" Grid.Column="5"/>
          <ComboBox x:Name="CmbLevel" Grid.Column="6" Width="236" Margin="16,0,10,0" SelectedIndex="0" VerticalContentAlignment="Center">
            <ComboBoxItem Content="Szybka diagnostyka (ok. 1 min)"/>
            <ComboBoxItem Content="Pełna diagnostyka (kilka min)"/>
          </ComboBox>
          <Button x:Name="BtnStart" Grid.Column="7" Style="{StaticResource PrimaryButton}" Content="▶  Rozpocznij diagnostykę"/>
          <Button x:Name="BtnCancel" Grid.Column="8" Content="Przerwij" IsEnabled="False" Margin="0"/>
        </Grid>
        <WrapPanel Margin="0,10,0,0">
          <TextBlock Text="Testy dodatkowe:" Foreground="#667085" VerticalAlignment="Center" Margin="0,0,12,0" ToolTip="Obciążają komputer, dlatego uruchamiane są tylko na żądanie - zaznacz przed rozpoczęciem diagnostyki."/>
          <CheckBox x:Name="ChkDisk" Content="szybkość dysku" Margin="0,0,16,0" VerticalAlignment="Center"/>
          <CheckBox x:Name="ChkCpu" Content="obciążenie CPU (45 s)" Margin="0,0,16,0" VerticalAlignment="Center" ToolTip="Pełne obciążenie wszystkich rdzeni - wykrywa dławienie (throttling) i przegrzewanie"/>
          <CheckBox x:Name="ChkNet" Content="prędkość internetu" Margin="0,0,16,0" VerticalAlignment="Center"/>
          <CheckBox x:Name="ChkVol" Content="skan NTFS (admin)" Margin="0,0,16,0" VerticalAlignment="Center" ToolTip="Skan systemu plików online, tylko odczyt - kilka minut"/>
          <CheckBox x:Name="ChkDism" Content="DISM ScanHealth (admin)" VerticalAlignment="Center" ToolTip="Pełna weryfikacja magazynu składników Windows - kilka minut"/>
          <CheckBox x:Name="ChkOffline" Content="tryb bez internetu" FontWeight="SemiBold" VerticalAlignment="Center" Margin="28,0,0,0"
                    ToolTip="Komputer celowo nie ma internetu (np. stanowisko serwisowe): testy łączności, prędkości i wyszukiwanie sterowników zostaną pominięte zamiast zgłaszać błędy."/>
        </WrapPanel>
      </StackPanel>
    </Border>

    <!-- pasek postępu -->
    <Border x:Name="ProgArea" Grid.Row="3" Padding="22,8,22,2" Visibility="Collapsed">
      <DockPanel>
        <TextBlock x:Name="ProgText" DockPanel.Dock="Right" Margin="14,-4,0,0" Foreground="#475467" MaxWidth="560" TextTrimming="CharacterEllipsis"/>
        <ProgressBar x:Name="Prog" Height="8" Minimum="0" Maximum="100" Foreground="#0F6CBD" Background="#DCE3EC" BorderThickness="0"/>
      </DockPanel>
    </Border>

    <!-- zawartość -->
    <Grid Grid.Row="4" Margin="14,12,14,6">
      <Grid.ColumnDefinitions><ColumnDefinition Width="236"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1" Padding="6">
        <ListBox x:Name="NavList" BorderThickness="0" Background="Transparent" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
          <ListBox.ItemTemplate>
            <DataTemplate>
              <DockPanel>
                <TextBlock DockPanel.Dock="Right" Text="{Binding Badge}" FontWeight="Bold" Foreground="#B54708" Margin="8,0,0,0"/>
                <Ellipse DockPanel.Dock="Left" Width="9" Height="9" Fill="{Binding Dot}" Margin="0,0,10,0" VerticalAlignment="Center"/>
                <TextBlock Text="{Binding Label}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
              </DockPanel>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>
      </Border>

      <Grid Grid.Column="1" Margin="12,0,0,0">
        <!-- strona: podsumowanie -->
        <ScrollViewer x:Name="PageSummary" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,0,8,10">
            <Border x:Name="WelcomeCard" Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1" Padding="26,22">
              <StackPanel>
                <TextBlock Text="Witaj w SerwisDiag" FontSize="22" FontWeight="SemiBold"/>
                <TextBlock TextWrapping="Wrap" Foreground="#475467" Margin="0,8,0,0" LineHeight="21"
                           Text="Program sprawdza komputer z systemem Windows 8, 8.1, 10 lub 11: sprzęt, dyski (SMART), baterię, awarie i błędy systemu, sterowniki, zabezpieczenia, aktualizacje, sieć oraz oprogramowanie i autostart."/>
                <TextBlock TextWrapping="Wrap" Foreground="#475467" Margin="0,10,0,0" LineHeight="21"
                           Text="Wpisz numer zlecenia i dane klienta (opcjonalnie), wybierz tryb i kliknij „Rozpocznij diagnostykę”. Po zakończeniu raport techniczny i raport dla klienta zapiszą się automatycznie."/>
                <TextBlock TextWrapping="Wrap" Foreground="#667085" Margin="0,14,0,0" FontSize="12.5" LineHeight="20"
                           Text="Program pracuje lokalnie i nie wysyła danych o komputerze (łączy się z internetem tylko w testach łączności i przy sprawdzaniu nowej wersji). Testy dodatkowe i narzędzia naprawcze uruchamiasz osobno, świadomie."/>
              </StackPanel>
            </Border>
            <StackPanel x:Name="ResultPanel" Visibility="Collapsed">
              <Border Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="9"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Border x:Name="VerdictBar" Grid.Column="0" CornerRadius="12,0,0,12" Background="#12B76A"/>
                  <DockPanel Grid.Column="1" Margin="20,16">
                    <WrapPanel x:Name="Counters" DockPanel.Dock="Right" VerticalAlignment="Center" HorizontalAlignment="Right" MaxWidth="420"/>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock x:Name="VerdictTitle" FontSize="22" FontWeight="Bold"/>
                      <TextBlock x:Name="VerdictText" Foreground="#667085" Margin="0,3,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                  </DockPanel>
                </Grid>
              </Border>
              <Border Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1" Padding="20,14" Margin="0,12,0,0">
                <StackPanel>
                  <TextBlock Text="Dane komputera" FontWeight="SemiBold" FontSize="15"/>
                  <ItemsControl x:Name="FactsList" Margin="0,8,0,0">
                    <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Columns="2"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
                    <ItemsControl.ItemTemplate>
                      <DataTemplate>
                        <DockPanel Margin="0,0,18,0">
                          <TextBlock DockPanel.Dock="Left" Text="{Binding Title}" Width="118" Foreground="#667085" Margin="0,4"/>
                          <TextBlock Text="{Binding Value}" TextWrapping="Wrap" Margin="0,4"/>
                        </DockPanel>
                      </DataTemplate>
                    </ItemsControl.ItemTemplate>
                  </ItemsControl>
                </StackPanel>
              </Border>
              <TextBlock Text="Wykryte problemy i zalecenia" FontWeight="SemiBold" FontSize="15" Margin="4,16,0,8"/>
              <TextBlock x:Name="NoIssuesText" Text="Nie wykryto problemów wymagających działania." Foreground="#067647" Margin="4,0,0,0" Visibility="Collapsed"/>
              <ItemsControl x:Name="IssuesList" ItemTemplate="{StaticResource IssueCard}"/>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- strona: kategoria -->
        <Grid x:Name="PageCategory" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition x:Name="RowFindings" Height="3*" MinHeight="150"/>
            <RowDefinition Height="8"/>
            <RowDefinition x:Name="RowTables" Height="2*" MinHeight="140"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1">
            <Grid>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <DockPanel Margin="16,12,16,6">
                <TextBlock x:Name="EmptyText" DockPanel.Dock="Right" Foreground="#667085" VerticalAlignment="Center"/>
                <TextBlock x:Name="CatTitle" FontSize="17" FontWeight="SemiBold"/>
              </DockPanel>
              <DataGrid x:Name="FindingsGrid" Grid.Row="1" AutoGenerateColumns="False" RowDetailsVisibilityMode="VisibleWhenSelected" Margin="4,0,4,4">
                <DataGrid.RowStyle>
                  <Style TargetType="DataGridRow">
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Status}" Value="crit"><Setter Property="Background" Value="#FFF6F5"/></DataTrigger>
                      <DataTrigger Binding="{Binding Status}" Value="warn"><Setter Property="Background" Value="#FFFBF0"/></DataTrigger>
                    </Style.Triggers>
                  </Style>
                </DataGrid.RowStyle>
                <DataGrid.Columns>
                  <DataGridTemplateColumn Header="Status" Width="112">
                    <DataGridTemplateColumn.CellTemplate>
                      <DataTemplate>
                        <Border Style="{StaticResource BadgeBorder}" HorizontalAlignment="Left" Margin="6,3">
                          <TextBlock Text="{Binding StatusLabel}" Style="{StaticResource BadgeText}"/>
                        </Border>
                      </DataTemplate>
                    </DataGridTemplateColumn.CellTemplate>
                  </DataGridTemplateColumn>
                  <DataGridTextColumn Header="Test" Binding="{Binding Title}" Width="250" ElementStyle="{StaticResource WrapText}"/>
                  <DataGridTextColumn Header="Wynik" Binding="{Binding Value}" Width="*" ElementStyle="{StaticResource WrapText}"/>
                </DataGrid.Columns>
                <DataGrid.RowDetailsTemplate>
                  <DataTemplate>
                    <StackPanel Margin="124,0,14,10">
                      <TextBlock Text="{Binding Details}" TextWrapping="Wrap" Foreground="#344054" FontSize="12.5">
                        <TextBlock.Style>
                          <Style TargetType="TextBlock"><Style.Triggers><DataTrigger Binding="{Binding Details}" Value=""><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers></Style>
                        </TextBlock.Style>
                      </TextBlock>
                      <Border Background="#F4F8FF" BorderBrush="#D6E4FF" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,6,0,0">
                        <Border.Style>
                          <Style TargetType="Border"><Style.Triggers><DataTrigger Binding="{Binding Advice}" Value=""><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers></Style>
                        </Border.Style>
                        <TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Zalecenie: "/><Run Text="{Binding Advice, Mode=OneWay}"/></TextBlock>
                      </Border>
                    </StackPanel>
                  </DataTemplate>
                </DataGrid.RowDetailsTemplate>
              </DataGrid>
            </Grid>
          </Border>
          <GridSplitter Grid.Row="1" Height="8" HorizontalAlignment="Stretch" Background="Transparent"/>
          <Border x:Name="TableArea" Grid.Row="2" Background="White" CornerRadius="12" BorderBrush="#E4E7EC" BorderThickness="1">
            <Grid>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <DockPanel Margin="16,10,16,6">
                <TextBlock Text="Dane szczegółowe:" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <ComboBox x:Name="TablesCombo" MinWidth="360" HorizontalAlignment="Left"/>
              </DockPanel>
              <DataGrid x:Name="TableGrid" Grid.Row="1" AutoGenerateColumns="True" Margin="4,0,4,4"/>
            </Grid>
          </Border>
        </Grid>

        <!-- strona: narzędzia -->
        <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="ToolsPanel" Margin="0,0,8,10"/>
        </ScrollViewer>
      </Grid>
    </Grid>

    <!-- stopka: przyciski zawijają się do drugiego wiersza na wąskim ekranie; komunikat pod nimi, gdy jest -->
    <Border Grid.Row="5" Background="White" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="22,8,22,8">
      <StackPanel>
        <WrapPanel>
          <Button x:Name="BtnFix" Content="Napraw problemy..." Style="{StaticResource PrimaryButton}" IsEnabled="False" Margin="0,2,8,2" ToolTip="Lista problemów z tej diagnostyki, które program może naprawić - z wyborem, co naprawić"/>
          <Button x:Name="BtnReportTech" Content="Raport techniczny" IsEnabled="False" Margin="0,2,8,2"/>
          <Button x:Name="BtnReportCust" Content="Raport dla klienta" IsEnabled="False" Margin="0,2,8,2"/>
          <Button x:Name="BtnPdf" Content="Zapisz PDF" IsEnabled="False" Margin="0,2,8,2" ToolTip="Raport dla klienta jako plik PDF - do wysłania mailem albo wydruku"/>
          <Button x:Name="BtnCompare" Content="Porównaj przed/po" Margin="0,2,8,2" ToolTip="Raport z naprawy: porównanie diagnostyki sprzed naprawy z diagnostyką po niej"/>
          <Button x:Name="BtnFolder" Content="Folder raportów" Margin="0,2,8,2"/>
          <Button x:Name="BtnMore" Content="Więcej ▾" Margin="0,2,8,2" ToolTip="Podsumowanie do schowka, raport anonimowy, cofanie napraw, kopia przed reinstalacją Windows"/>
        </WrapPanel>
        <TextBlock x:Name="FooterText" Foreground="#667085" Margin="2,5,0,0" TextTrimming="CharacterEllipsis">
          <TextBlock.Style>
            <Style TargetType="TextBlock"><Style.Triggers><Trigger Property="Text" Value=""><Setter Property="Visibility" Value="Collapsed"/></Trigger></Style.Triggers></Style>
          </TextBlock.Style>
        </TextBlock>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

$global:SdUiSettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ustawienia serwisu" Width="600" Height="640" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Dane serwisu (widoczne w nagłówku raportów)" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,12"/>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="42"/><RowDefinition Height="36"/>
        <RowDefinition Height="36"/><RowDefinition Height="40"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Text="Nazwa serwisu" VerticalAlignment="Center"/><TextBox x:Name="SShop" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" Height="30" Padding="6,4"/>
      <TextBlock Grid.Row="1" Text="Telefon" VerticalAlignment="Center"/><TextBox x:Name="SPhone" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Height="30" Padding="6,4"/>
      <TextBlock Grid.Row="2" Text="E-mail / WWW" VerticalAlignment="Center"/><TextBox x:Name="SMail" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Height="30" Padding="6,4"/>
      <TextBlock Grid.Row="3" Text="Adres" VerticalAlignment="Center"/><TextBox x:Name="SAddr" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2" Height="30" Padding="6,4"/>
      <TextBlock Grid.Row="4" Text="Technik" VerticalAlignment="Center"/><TextBox x:Name="STech" Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2" Height="30" Padding="6,4"/>
      <TextBlock Grid.Row="5" Text="Logo (PNG/JPG)" VerticalAlignment="Center"/><TextBox x:Name="SLogo" Grid.Row="5" Grid.Column="1" Height="30" Padding="6,4"/><Button x:Name="SLogoBtn" Grid.Row="5" Grid.Column="2" Content="Wybierz..." Margin="8,0,0,0" Height="30" Padding="10,0"/>
      <TextBlock Grid.Row="6" Text="Folder raportów" VerticalAlignment="Center"/><TextBox x:Name="SDir" Grid.Row="6" Grid.Column="1" Height="30" Padding="6,4"/><Button x:Name="SDirBtn" Grid.Row="6" Grid.Column="2" Content="Wybierz..." Margin="8,0,0,0" Height="30" Padding="10,0"/>
      <TextBlock Grid.Row="7" Text="Po diagnostyce" VerticalAlignment="Center"/>
      <ComboBox x:Name="SOpen" Grid.Row="7" Grid.Column="1" Grid.ColumnSpan="2" Height="30" VerticalContentAlignment="Center"
                ToolTip="Raport techniczny zawiera dane prywatne (numery seryjne, klucz OEM) - nie otwieraj go automatycznie, jeśli ekran widzi klient.">
        <ComboBoxItem Content="nie otwieraj raportu"/>
        <ComboBoxItem Content="otwórz raport dla klienta"/>
        <ComboBoxItem Content="otwórz raport techniczny"/>
      </ComboBox>
      <TextBlock Grid.Row="8" Text="PDF" VerticalAlignment="Center"/>
      <CheckBox x:Name="SPdf" Grid.Row="8" Grid.Column="1" Grid.ColumnSpan="2" VerticalAlignment="Center" Content="zapisuj też raport dla klienta jako PDF (Microsoft Edge)"/>
      <TextBlock Grid.Row="9" Text="Aktualizacje" VerticalAlignment="Center"/>
      <CheckBox x:Name="SUpd" Grid.Row="9" Grid.Column="1" Grid.ColumnSpan="2" VerticalAlignment="Center" Content="sprawdzaj raz na dobę, czy jest nowa wersja (GitHub)"/>
      <TextBlock Grid.Row="10" Text="Monitorowanie" VerticalAlignment="Center"/>
      <CheckBox x:Name="SMon" Grid.Row="10" Grid.Column="1" VerticalAlignment="Center" Content="monitoruj system w tle" ToolTip="Ikona przy zegarze i powiadomienia o nowych problemach; uruchamia się przy logowaniu."/>
      <ComboBox x:Name="SMonInt" Grid.Row="10" Grid.Column="2" Width="140" Height="30" Margin="8,0,0,0" VerticalContentAlignment="Center"/>
    </Grid>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="SSave" Content="Zapisz" Width="100" Height="32" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="SCancel" Content="Anuluj" Width="100" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

$global:SdUiCompareXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Porównanie przed i po naprawie" Width="660" Height="450" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel>
      <TextBlock Text="Raport z naprawy: porównanie przed i po" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,12"
                 Text="Wskaż raporty JSON zapisane przez program (folder raportów). Powstanie raport techniczny i raport dla klienta z listą rozwiązanych i pozostałych problemów."/>
    </StackPanel>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height="38"/><RowDefinition Height="38"/></Grid.RowDefinitions>
      <TextBlock Text="Przed naprawą" VerticalAlignment="Center"/>
      <TextBox x:Name="CBefore" Grid.Column="1" Height="30" Padding="6,4"/>
      <Button x:Name="CBeforeBtn" Grid.Column="2" Content="Wybierz..." Margin="8,0,0,0" Height="30" Padding="10,0"/>
      <TextBlock Grid.Row="1" Text="Po naprawie" VerticalAlignment="Center"/>
      <TextBox x:Name="CAfter" Grid.Row="1" Grid.Column="1" Height="30" Padding="6,4"/>
      <Button x:Name="CAfterBtn" Grid.Row="1" Grid.Column="2" Content="Wybierz..." Margin="8,0,0,0" Height="30" Padding="10,0"/>
    </Grid>
    <DockPanel Grid.Row="2" Margin="0,12,0,0">
      <TextBlock DockPanel.Dock="Top" Text="Wykonane czynności (trafią do obu raportów, np. wymiana dysku, czyszczenie, aktualizacja sterowników)" TextWrapping="Wrap" Margin="0,0,0,6"/>
      <TextBox x:Name="CWork" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top" Padding="6,4"/>
    </DockPanel>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="CMake" Content="Utwórz porównanie" Height="32" Padding="14,0" Margin="0,0,8,0"/>
      <Button x:Name="CCancel" Content="Anuluj" Width="100" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

$global:SdUiDriversXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sterowniki z Windows Update" Width="780" Height="560" MinWidth="600" MinHeight="420" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Sterowniki z Windows Update" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,10"
               Text="Oficjalne, podpisane sterowniki dopasowane do urządzeń tego komputera. Zaznaczone są sterowniki zalecane i te, które naprawiają urządzenia z błędami; opcjonalne zaznacz sam."/>
    <Border Grid.Row="2" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="DList" Margin="12,10"/></ScrollViewer>
    </Border>
    <StackPanel Grid.Row="3" Margin="0,10,0,0">
      <CheckBox x:Name="DRestore" Content="Przed instalacją utwórz punkt przywracania systemu (zalecane)" IsChecked="True"/>
      <TextBlock x:Name="DStatus" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#475467"/>
      <ProgressBar x:Name="DProg" Height="6" Margin="0,6,0,0" IsIndeterminate="True" Foreground="#0F6CBD"/>
    </StackPanel>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="DSearch" Content="Wyszukaj ponownie" Height="32" Padding="14,0" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="DInstall" Content="Zainstaluj zaznaczone" Height="32" Padding="14,0" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="DClose" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

$global:SdUiFixesXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Naprawa problemów" Width="880" Height="680" MinWidth="680" MinHeight="480" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Naprawa problemów wykrytych w diagnostyce" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,10"
               Text="Zaznacz, co program ma naprawić. Zalecane naprawy są zaznaczone, ryzykowniejsze zaznaczasz sam. Przed zmianami program tworzy punkt przywracania, a każdą zmianę zapisuje w dzienniku napraw z poprzednią wartością - zmienione ustawienia można potem cofnąć. Program jest udostępniany bez gwarancji: naprawy wykonujesz na własną odpowiedzialność."/>
    <Border Grid.Row="2" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="FList" Margin="14,10"/></ScrollViewer>
    </Border>
    <StackPanel Grid.Row="3" Margin="0,10,0,0">
      <CheckBox x:Name="FRestore" Content="Przed naprawą utwórz punkt przywracania systemu (zalecane)" IsChecked="True"/>
      <TextBlock x:Name="FStatus" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#475467"/>
      <ProgressBar x:Name="FProg" Height="6" Margin="0,6,0,0" Minimum="0" Maximum="100" Foreground="#0F6CBD" IsIndeterminate="True"/>
    </StackPanel>
    <DockPanel Grid.Row="4" Margin="0,12,0,0" LastChildFill="False">
      <Button x:Name="FRecommended" DockPanel.Dock="Left" Content="Zaznacz zalecane" Height="32" Padding="12,0" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="FNone" DockPanel.Dock="Left" Content="Odznacz wszystkie" Height="32" Padding="12,0" IsEnabled="False"/>
      <Button x:Name="FClose" DockPanel.Dock="Right" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
      <Button x:Name="FRun" DockPanel.Dock="Right" Content="Napraw zaznaczone" Height="32" Padding="14,0" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="FRescan" DockPanel.Dock="Right" Content="Diagnostyka ponownie" Height="32" Padding="14,0" Margin="0,0,8,0" Visibility="Collapsed"/>
    </DockPanel>
  </Grid>
</Window>
'@

$global:SdUiMissingXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Brakujące sterowniki" Width="880" Height="480" MinWidth="640" MinHeight="360" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Urządzenia bez sterownika lub z błędem" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,10"
               Text="Zaznacz urządzenie i wyszukaj sterownik w Katalogu Microsoft Update po identyfikatorze sprzętu. Pobrany plik .cab rozpakuj i wskaż w Menedżerze urządzeń (Aktualizuj sterownik &gt; Przeglądaj mój komputer)."/>
    <DataGrid x:Name="MGrid" Grid.Row="2" AutoGenerateColumns="True" IsReadOnly="True" SelectionMode="Single" HeadersVisibility="Column"
              CanUserAddRows="False" RowHeaderWidth="0" Background="White" BorderBrush="#E4E7EC" GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#EEF0F3"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="MCatalog" Content="Szukaj w Katalogu Microsoft" Height="32" Padding="14,0" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="MCopy" Content="Kopiuj identyfikator" Height="32" Padding="14,0" Margin="0,0,8,0"/>
      <Button x:Name="MVendor" Content="Strona producenta" Height="32" Padding="14,0" Margin="0,0,8,0"/>
      <Button x:Name="MClose" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

$global:SdUiUndoXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cofanie napraw" Width="860" Height="620" MinWidth="640" MinHeight="440" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Cofanie zmian wprowadzonych przez naprawy" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,10"
               Text="Program przywraca poprzednie ustawienia zapisane w dzienniku napraw: wartości rejestru, typ uruchamiania usług, zaporę i SMB1. Nie cofa DISM, SFC, czyszczenia plików ani instalacji sterowników - do tego służy punkt przywracania systemu. Ustawienia zmienione ponownie po naprawie są pomijane."/>
    <DockPanel Grid.Row="2" Margin="0,0,0,8">
      <Button x:Name="UPick" DockPanel.Dock="Right" Content="Wybierz dziennik..." Height="30" Padding="10,0" Margin="8,0,0,0"/>
      <TextBox x:Name="UFile" IsReadOnly="True" Height="30" Padding="6,4"/>
    </DockPanel>
    <Border Grid.Row="3" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="UList" Margin="14,10"/></ScrollViewer>
    </Border>
    <TextBlock x:Name="UStatus" Grid.Row="4" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#475467"/>
    <DockPanel Grid.Row="5" Margin="0,12,0,0" LastChildFill="False">
      <Button x:Name="URestore" DockPanel.Dock="Left" Content="Przywracanie systemu..." Height="32" Padding="12,0" ToolTip="Kreator przywracania systemu Windows (rstrui) - cofa całość do punktu przywracania sprzed napraw"/>
      <Button x:Name="UClose" DockPanel.Dock="Right" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
      <Button x:Name="URun" DockPanel.Dock="Right" Content="Cofnij zaznaczone" Height="32" Padding="14,0" Margin="0,0,8,0" IsEnabled="False"/>
    </DockPanel>
  </Grid>
</Window>
'@

$global:SdUiBackupXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kopia przed reinstalacją Windows" Width="780" Height="650" MinWidth="600" MinHeight="460" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Kopia przed reinstalacją Windows" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#667085" Margin="0,4,0,10"
               Text="Zapisuje w jednym folderze to, co zwykle ginie przy reinstalacji systemu. Program niczego nie zmienia na komputerze. Folder wybierz na pendrive albo dysku innym niż systemowy. Plików użytkownika (dokumenty, zdjęcia) program nie kopiuje."/>
    <Border Grid.Row="2" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="BList" Margin="14,10"/></ScrollViewer>
    </Border>
    <DockPanel Grid.Row="3" Margin="0,10,0,0">
      <TextBlock DockPanel.Dock="Left" Text="Folder docelowy" VerticalAlignment="Center" Margin="0,0,10,0"/>
      <Button x:Name="BPick" DockPanel.Dock="Right" Content="Wybierz..." Height="30" Padding="10,0" Margin="8,0,0,0"/>
      <TextBox x:Name="BDest" Height="30" Padding="6,4"/>
    </DockPanel>
    <StackPanel Grid.Row="4" Margin="0,8,0,0">
      <TextBlock x:Name="BStatus" TextWrapping="Wrap" Foreground="#475467"/>
      <ProgressBar x:Name="BProg" Height="6" Margin="0,6,0,0" IsIndeterminate="True" Foreground="#0F6CBD" Visibility="Collapsed"/>
    </StackPanel>
    <DockPanel Grid.Row="5" Margin="0,12,0,0" LastChildFill="False">
      <Button x:Name="BOpen" DockPanel.Dock="Left" Content="Otwórz folder kopii" Height="32" Padding="12,0" Visibility="Collapsed"/>
      <Button x:Name="BClose" DockPanel.Dock="Right" Content="Zamknij" Width="100" Height="32" IsCancel="True"/>
      <Button x:Name="BRun" DockPanel.Dock="Right" Content="Utwórz kopię" Height="32" Padding="14,0" Margin="0,0,8,0"/>
    </DockPanel>
  </Grid>
</Window>
'@

$global:SdUiAboutXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="O programie" Width="620" Height="600" MinWidth="480" MinHeight="420" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13" Background="#F3F5F9">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel>
      <TextBlock Text="SerwisDiag" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock x:Name="AVersion" Foreground="#667085" Margin="0,2,0,0"/>
    </StackPanel>
    <Border Grid.Row="1" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8" Margin="0,12,0,0">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="APanel" Margin="16,12"/></ScrollViewer>
    </Border>
    <DockPanel Grid.Row="2" Margin="0,14,0,0" LastChildFill="False">
      <Button x:Name="ALicense" DockPanel.Dock="Left" Content="Tekst licencji" Height="32" Padding="12,0" Margin="0,0,8,0"/>
      <Button x:Name="AUpdate" DockPanel.Dock="Left" Content="Sprawdź nową wersję" Height="32" Padding="12,0" Margin="0,0,8,0"/>
      <Button x:Name="AClose" DockPanel.Dock="Right" Content="Zamknij" Width="100" Height="32" IsCancel="True" IsDefault="True"/>
    </DockPanel>
  </Grid>
</Window>
'@

$global:SdStatusColors = @{
    crit  = @('#FEE4E2', '#B42318')
    warn  = @('#FEF0C7', '#93370D')
    ok    = @('#D1FADF', '#067647')
    info  = @('#E0EAFF', '#175CD3')
    skip  = @('#EAECF0', '#475467')
    error = @('#EBE9FE', '#6941C6')
}

function Get-SdBrush {
    param([string]$Hex)
    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex)
}

function Show-SdMessage {
    param([string]$Text, [string]$Title = 'SerwisDiag', [string]$Icon = 'Information', [string]$Buttons = 'OK')
    $ui = $global:SdUi
    if ($ui -and $ui.SelfTest) { return 'OK' }
    $owner = $null
    if ($ui -and $ui.Window) { $owner = $ui.Window }
    if ($owner) { return [string][System.Windows.MessageBox]::Show($owner, $Text, $Title, [System.Windows.MessageBoxButton]::$Buttons, [System.Windows.MessageBoxImage]::$Icon) }
    return [string][System.Windows.MessageBox]::Show($Text, $Title, [System.Windows.MessageBoxButton]::$Buttons, [System.Windows.MessageBoxImage]::$Icon)
}

function Get-SdFitWindowSize {
    # Rozmiar okna dopasowany do obszaru roboczego ekranu (bez paska zadań). Okno o stałym rozmiarze na laptopie 1366x768
    # albo przy powiększeniu 125-150% wychodziłoby poza ekran razem z przyciskami na dole.
    param([double]$Width, [double]$Height, [double]$MinWidth, [double]$MinHeight, [double]$AreaWidth, [double]$AreaHeight)
    $w = [math]::Min($Width, $AreaWidth)
    $h = [math]::Min($Height, $AreaHeight)
    return [pscustomobject]@{
        Width = $w; Height = $h; MinWidth = [math]::Min($MinWidth, $w); MinHeight = [math]::Min($MinHeight, $h)
        Maximize = ($Width -gt $AreaWidth -or $Height -gt $AreaHeight)
    }
}

function Get-SdUiWorkArea {
    # Obszar roboczy ekranu głównego w jednostkach WPF. Autotest może udawać mały ekran: SERWISDIAG_TEST_AREA=1093x614.
    $wa = [System.Windows.SystemParameters]::WorkArea
    $r = [pscustomobject]@{ Width = [double]$wa.Width; Height = [double]$wa.Height }
    if ($global:SdUi -and $global:SdUi.SelfTest -and [string]$env:SERWISDIAG_TEST_AREA -match '^(\d+)x(\d+)$') {
        $r.Width = [double]$Matches[1]; $r.Height = [double]$Matches[2]
    }
    return $r
}

function Set-SdUiWindowFit {
    # Dopasowuje okno do ekranu; okno główne na zbyt małym ekranie otwiera się zmaksymalizowane.
    param($Window, [switch]$AllowMaximize)
    try {
        $wa = Get-SdUiWorkArea
        $f = Get-SdFitWindowSize -Width $Window.Width -Height $Window.Height -MinWidth $Window.MinWidth -MinHeight $Window.MinHeight -AreaWidth $wa.Width -AreaHeight $wa.Height
        $Window.MinWidth = $f.MinWidth; $Window.MinHeight = $f.MinHeight
        $Window.Width = $f.Width; $Window.Height = $f.Height
        if ($f.Maximize -and $AllowMaximize) { $Window.WindowState = 'Maximized' }
    } catch { Write-SdLog ('Dopasowanie okna: ' + $_.Exception.Message) 'WARN' }
}

function Set-SdUiResultButtons {
    # Przyciski i polecenia menu, które wymagają wyników diagnostyki.
    param([bool]$Enabled)
    $ui = $global:SdUi; $c = $ui.C
    foreach ($b in 'BtnFix', 'BtnReportTech', 'BtnReportCust', 'BtnPdf') { $c[$b].IsEnabled = $Enabled }
    foreach ($k in 'Copy', 'Anon') { if ($ui.Menu -and $ui.Menu[$k]) { $ui.Menu[$k].IsEnabled = $Enabled } }
}

function Initialize-SdUiMoreMenu {
    # Menu „Więcej” w stopce (budowane w kodzie - elementy menu kontekstowego nie należą do drzewa nazw okna).
    $ui = $global:SdUi
    $ui.Menu = @{}
    $cm = New-Object System.Windows.Controls.ContextMenu
    $items = @(
        @{ K = 'Copy'; H = 'Kopiuj podsumowanie do schowka'; A = {
                $u = $global:SdUi
                if ($u.Result) {
                    try { [System.Windows.Clipboard]::SetText((New-SdTextReport -Result $u.Result -Settings $u.Settings)); $u.C.FooterText.Text = 'Skopiowano podsumowanie do schowka.' }
                    catch { $u.C.FooterText.Text = 'Nie udało się skopiować do schowka.' }
                }
            }
        }
        @{ K = 'Anon'; H = 'Raport anonimowy (do pokazania na forum)'; A = { Invoke-SdUiAnonymous } }
        @{ K = '' }
        @{ K = 'Undo'; H = 'Cofnij naprawy z dziennika...'; A = { Show-SdUiUndo } }
        @{ K = 'Backup'; H = 'Kopia przed reinstalacją Windows...'; A = { Show-SdUiBackup } }
    )
    foreach ($it in $items) {
        if (-not $it.K) { [void]$cm.Items.Add((New-Object System.Windows.Controls.Separator)); continue }
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $it.H
        $mi.Add_Click($it.A)
        [void]$cm.Items.Add($mi)
        $ui.Menu[$it.K] = $mi
    }
    $ui.Menu['Copy'].IsEnabled = $false; $ui.Menu['Anon'].IsEnabled = $false
    $ui.C.BtnMore.ContextMenu = $cm
    $ui.C.BtnMore.Add_Click({
            $b = $global:SdUi.C.BtnMore
            $b.ContextMenu.PlacementTarget = $b
            $b.ContextMenu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Top
            $b.ContextMenu.IsOpen = $true
        })
}

function ConvertTo-SdUiRows {
    param($Findings)
    $list = New-Object 'System.Collections.Generic.List[SdUiRow]'
    foreach ($f in @($Findings)) {
        if ($null -eq $f) { continue }
        $r = New-Object SdUiRow
        $r.Status = [string]$f.Status
        $r.StatusLabel = $global:SdStatusInfo[[string]$f.Status].Label
        $r.Title = [string]$f.Title
        $r.Value = [string]$f.Value
        $r.Details = [string]$f.Details
        $r.Advice = [string]$f.Advice
        $r.Category = [string]$f.Category
        $r.CategoryLabel = Get-SdCategoryLabel ([string]$f.Category)
        $r.Tag = $(if ($f.Private) { 'prywatne' } else { '' })
        [void]$list.Add($r)
    }
    return , $list
}

function ConvertTo-SdDataTable {
    param($Table)
    $dt = New-Object System.Data.DataTable
    foreach ($col in $Table.Columns) { [void]$dt.Columns.Add([string]$col, [string]) }
    foreach ($row in $Table.Rows) {
        $dr = $dt.NewRow()
        foreach ($col in $Table.Columns) {
            $p = $row.PSObject.Properties[[string]$col]
            if ($p -and $null -ne $p.Value) { $dr[[string]$col] = [string]$p.Value } else { $dr[[string]$col] = '' }
        }
        [void]$dt.Rows.Add($dr)
    }
    return , $dt
}

# ------------------------------------------------------------------ odświeżanie widoków

function Initialize-SdUiNav {
    $ui = $global:SdUi
    $ui.Nav = New-Object 'System.Collections.ObjectModel.ObservableCollection[SdNavItem]'
    $add = {
        param($k, $l)
        $i = New-Object SdNavItem
        $i.Key = $k; $i.Label = $l
        [void]$ui.Nav.Add($i)
    }
    & $add 'summary' 'Podsumowanie'
    foreach ($c in $global:SdCategories) { if ($c.Key -ne 'tests') { & $add $c.Key $c.Label } }
    & $add 'tools' 'Narzędzia serwisowe'
    $ui.C.NavList.ItemsSource = $ui.Nav
    $ui.C.NavList.SelectedIndex = 0
}

function Update-SdUiNav {
    $ui = $global:SdUi
    if (-not $ui.Ctx) { return }
    $snap = @($ui.Ctx.Findings.ToArray())
    $hasTests = (@($snap | Where-Object { $_.Category -eq 'tests' }).Count -gt 0)
    $present = @($ui.Nav | Where-Object { $_.Key -eq 'tests' }).Count -gt 0
    if ($hasTests -and -not $present) {
        $i = New-Object SdNavItem
        $i.Key = 'tests'; $i.Label = Get-SdCategoryLabel 'tests'
        $ui.Nav.Insert($ui.Nav.Count - 1, $i)
    }
    $all = @{ crit = 0; warn = 0 }
    foreach ($item in $ui.Nav) {
        if ($item.Key -eq 'tools') { continue }
        if ($item.Key -eq 'summary') { continue }
        $cf = @($snap | Where-Object { $_.Category -eq $item.Key })
        $crit = @($cf | Where-Object { $_.Status -eq 'crit' }).Count
        $warn = @($cf | Where-Object { $_.Status -eq 'warn' }).Count
        $all.crit += $crit; $all.warn += $warn
        $dot = '#D0D5DD'
        if ($cf.Count -gt 0) { $dot = '#12B76A' }
        if ($warn -gt 0) { $dot = '#F79009' }
        if ($crit -gt 0) { $dot = '#D92D20' }
        $item.Dot = $dot
        $item.Badge = $(if (($crit + $warn) -gt 0) { [string]($crit + $warn) } else { '' })
    }
    $sum = $ui.Nav | Where-Object { $_.Key -eq 'summary' } | Select-Object -First 1
    if ($sum) {
        $sum.Dot = $(if ($all.crit -gt 0) { '#D92D20' } elseif ($all.warn -gt 0) { '#F79009' } elseif ($snap.Count -gt 0) { '#12B76A' } else { '#D0D5DD' })
        $sum.Badge = $(if (($all.crit + $all.warn) -gt 0) { [string]($all.crit + $all.warn) } else { '' })
    }
}

function Update-SdUiSummary {
    $ui = $global:SdUi; $c = $ui.C
    $hasData = ($ui.Ctx -and $ui.Ctx.Findings.Count -gt 0)
    $c.WelcomeCard.Visibility = $(if ($hasData) { 'Collapsed' } else { 'Visible' })
    $c.ResultPanel.Visibility = $(if ($hasData) { 'Visible' } else { 'Collapsed' })
    if (-not $hasData) { return }
    $res = Get-SdResult
    $v = $res.Verdict
    $color = switch ($v.Level) { 'crit' { '#D92D20' } 'warn' { '#F79009' } default { '#12B76A' } }
    $tcolor = switch ($v.Level) { 'crit' { '#B42318' } 'warn' { '#B54708' } default { '#067647' } }
    $c.VerdictBar.Background = Get-SdBrush $color
    $c.VerdictTitle.Text = $v.Title
    $c.VerdictTitle.Foreground = Get-SdBrush $tcolor
    $hint = ''
    if (-not $ui.Scanning -and ([int]$res.Counts['crit'] + [int]$res.Counts['warn']) -gt 0) { $hint = ' Kliknij „Napraw problemy...” na dole okna, aby zobaczyć, co program naprawi sam.' }
    $c.VerdictText.Text = $(if ($ui.Scanning) { 'Diagnostyka w toku - wyniki uzupełniają się na bieżąco...' } else { $v.Text + $hint })

    $c.Counters.Children.Clear()
    foreach ($pair in @(@('crit', 'krytyczne'), @('warn', 'ostrzeżenia'), @('ok', 'w porządku'), @('info', 'informacje'), @('skip', 'pominięte'), @('error', 'błędy testów'))) {
        $n = [int]$res.Counts[$pair[0]]
        if ($n -le 0) { continue }
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = New-Object System.Windows.CornerRadius(12)
        $b.Padding = New-Object System.Windows.Thickness(11, 4, 11, 4)
        $b.Margin = New-Object System.Windows.Thickness(6, 3, 0, 3)
        $b.Background = Get-SdBrush $global:SdStatusColors[$pair[0]][0]
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = ('{0} {1}' -f $n, $pair[1])
        $t.FontSize = 12; $t.FontWeight = [System.Windows.FontWeights]::SemiBold
        $t.Foreground = Get-SdBrush $global:SdStatusColors[$pair[0]][1]
        $b.Child = $t
        [void]$c.Counters.Children.Add($b)
    }

    $facts = New-Object 'System.Collections.Generic.List[SdUiRow]'
    $m = $res.Meta
    foreach ($p in @(@('Komputer', 'Model'), @('System', 'OS'), @('Procesor', 'Cpu'), @('Pamięć RAM', 'Ram'), @('Dyski', 'Disks'), @('Grafika', 'Gpu'), @('BIOS / UEFI', 'Bios'), @('Nazwa komputera', 'ComputerName'), @('Numer seryjny', 'Serial'), @('Typ obudowy', 'Chassis'))) {
        if ($m[$p[1]]) { $r = New-Object SdUiRow; $r.Title = $p[0]; $r.Value = [string]$m[$p[1]]; [void]$facts.Add($r) }
    }
    if ($m['BatteryHealth']) { $r = New-Object SdUiRow; $r.Title = 'Kondycja baterii'; $r.Value = ('{0}% pojemności fabrycznej' -f $m['BatteryHealth']); [void]$facts.Add($r) }
    if ($m['Stability']) { $r = New-Object SdUiRow; $r.Title = 'Indeks stabilności'; $r.Value = ('{0} / 10' -f $m['Stability']); [void]$facts.Add($r) }
    $c.FactsList.ItemsSource = $facts

    $order = @{}; $i = 0
    foreach ($cat in $global:SdCategories) { $order[$cat.Key] = $i; $i++ }
    $issues = @($res.Findings | Where-Object { $_.Status -eq 'crit' -or $_.Status -eq 'warn' } |
            Sort-Object @{ Expression = { if ($_.Status -eq 'crit') { 0 } else { 1 } } }, @{ Expression = { if ($order.ContainsKey($_.Category)) { $order[$_.Category] } else { 99 } } })
    $c.IssuesList.ItemsSource = (ConvertTo-SdUiRows $issues)
    $c.NoIssuesText.Visibility = $(if ($issues.Count -eq 0 -and -not $ui.Scanning) { 'Visible' } else { 'Collapsed' })
}

function Set-SdUiRowHeight {
    param($Row, [double]$Stars, [double]$Min)
    if ($global:SdUi.Compact) { $Min = [math]::Round($Min * 0.6) }   # niski ekran: mniej miejsca na listy, ale stopka widoczna
    $Row.MinHeight = $Min
    if ($Stars -le 0) { $Row.Height = New-Object System.Windows.GridLength(0) } else { $Row.Height = New-Object System.Windows.GridLength($Stars, [System.Windows.GridUnitType]::Star) }
}

function Update-SdUiTable {
    $ui = $global:SdUi; $c = $ui.C
    $idx = $c.TablesCombo.SelectedIndex
    if ($idx -lt 0 -or -not $ui.CurrentTables -or $idx -ge @($ui.CurrentTables).Count) { $c.TableGrid.ItemsSource = $null; return }
    $dt = ConvertTo-SdDataTable (@($ui.CurrentTables)[$idx])
    $c.TableGrid.ItemsSource = $dt.DefaultView
}

function Update-SdUiCategory {
    param([string]$Key)
    $ui = $global:SdUi; $c = $ui.C
    $c.CatTitle.Text = Get-SdCategoryLabel $Key
    $snap = @(); $tables = @()
    if ($ui.Ctx) {
        $snap = @($ui.Ctx.Findings.ToArray() | Where-Object { $_.Category -eq $Key })
        $tables = @($ui.Ctx.Tables.ToArray() | Where-Object { $_.Category -eq $Key })
    }
    $c.FindingsGrid.ItemsSource = (ConvertTo-SdUiRows $snap)
    $c.EmptyText.Text = $(if ($snap.Count -eq 0) { $(if ($ui.Ctx) { 'Brak wyników w tej kategorii' } else { 'Uruchom diagnostykę, aby zobaczyć wyniki' }) } else { 'Kliknij wiersz, aby zobaczyć szczegóły i zalecenia' })
    $ui.CurrentTables = $tables
    $names = @($tables | ForEach-Object { '{0} ({1})' -f $_.Name, @($_.Rows).Count })
    $prev = $c.TablesCombo.SelectedIndex
    $ui.SuppressTable = $true
    $c.TablesCombo.ItemsSource = $names
    if ($names.Count -gt 0) {
        $c.TablesCombo.SelectedIndex = [math]::Max([math]::Min($prev, $names.Count - 1), 0)
        $c.TableArea.Visibility = 'Visible'
        Set-SdUiRowHeight $c.RowFindings 3 150
        Set-SdUiRowHeight $c.RowTables 2 140
    } else {
        $c.TableArea.Visibility = 'Collapsed'
        $c.TableGrid.ItemsSource = $null
        Set-SdUiRowHeight $c.RowFindings 1 150
        Set-SdUiRowHeight $c.RowTables 0 0
    }
    $ui.SuppressTable = $false
    Update-SdUiTable
}

function Show-SdUiPage {
    param([string]$Key)
    $ui = $global:SdUi; $c = $ui.C
    $ui.Selected = $Key
    $c.PageSummary.Visibility = 'Collapsed'; $c.PageCategory.Visibility = 'Collapsed'; $c.PageTools.Visibility = 'Collapsed'
    if ($Key -eq 'summary') { $c.PageSummary.Visibility = 'Visible'; Update-SdUiSummary }
    elseif ($Key -eq 'tools') { $c.PageTools.Visibility = 'Visible' }
    else { $c.PageCategory.Visibility = 'Visible'; Update-SdUiCategory $Key }
}

function Refresh-SdUiPage {
    $ui = $global:SdUi
    Update-SdUiNav
    $k = $ui.Selected
    if (-not $k) { $k = 'summary' }
    if ($k -eq 'summary') { Update-SdUiSummary } elseif ($k -ne 'tools') { Update-SdUiCategory $k }
}

# ------------------------------------------------------------------ skanowanie

function Start-SdUiScan {
    $ui = $global:SdUi; $c = $ui.C
    if ($ui.Scanning) { return }
    $level = 'Quick'
    if ($c.CmbLevel.SelectedIndex -eq 1) { $level = 'Full' }
    $tests = @()
    if ($c.ChkDisk.IsChecked) { $tests += 'tt.disk' }
    if ($c.ChkCpu.IsChecked) { $tests += 'tt.cpu' }
    if ($c.ChkNet.IsChecked) { $tests += 'tt.net' }
    if ($c.ChkVol.IsChecked) { $tests += 'tt.volscan' }
    if ($c.ChkDism.IsChecked) { $tests += 'tt.dism' }
    if ($tests -contains 'tt.cpu' -and -not $ui.SelfTest) {
        $r = Show-SdMessage 'Test obciążeniowy CPU będzie przez ok. 45 sekund obciążał wszystkie rdzenie - wentylatory mogą mocno przyspieszyć. Kontynuować?' 'Test obciążeniowy' 'Question' 'YesNo'
        if ($r -ne 'Yes') { return }
    }
    $ctx = New-SdContext -Root $ui.Root -Level $level -Tests $tests -Offline:([bool]$c.ChkOffline.IsChecked) -Synchronized
    $ctx.Meta['Ticket'] = $c.TxtTicket.Text.Trim()
    $ctx.Meta['Customer'] = $c.TxtCustomer.Text.Trim()
    $ctx.Meta['DeviceNote'] = $c.TxtNote.Text.Trim()
    $ctx.Meta['Technician'] = [string]$ui.Settings.Technician
    if ($global:SdIntegrity) { $ctx.Meta['Integrity'] = [string]$global:SdIntegrity.Summary }
    $ui.Ctx = $ctx
    $global:SD = $ctx          # w wątku interfejsu: dla Get-SdResult i funkcji formatujących
    $ui.Result = $null; $ui.ReportPaths = $null; $ui.ShownCount = -1; $ui.Scanning = $true; $ui.CancelRequested = $false
    $c.BtnStart.IsEnabled = $false; $c.BtnCancel.IsEnabled = $true
    Set-SdUiResultButtons $false
    $c.ProgArea.Visibility = 'Visible'; $c.Prog.Value = 0; $c.Prog.Maximum = 100
    $c.ProgText.Text = 'Przygotowanie...'
    $c.FooterText.Text = ''
    Refresh-SdUiPage

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('SdCtx', $ctx)
    $rs.SessionStateProxy.SetVariable('SdRoot', $ui.Root)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            $ErrorActionPreference = 'SilentlyContinue'
            . (Join-Path $SdRoot 'lib\Load.ps1')
            $global:SD = $SdCtx
            Invoke-SdScan
        })
    $ui.Rs = $rs; $ui.Ps = $ps
    $ui.Async = $ps.BeginInvoke()
    $ui.Timer.Start()
}

function Stop-SdUiScan {
    $ui = $global:SdUi
    if (-not $ui.Scanning) { return }
    $ui.CancelRequested = $true
    $ui.CancelAt = Get-Date
    $ui.Ctx.Cancel = $true
    $ui.C.BtnCancel.IsEnabled = $false
    $ui.C.ProgText.Text = 'Przerywanie po zakończeniu bieżącego testu...'
}

function Complete-SdUiScan {
    $ui = $global:SdUi; $c = $ui.C
    $ui.Timer.Stop()
    try { [void]$ui.Ps.EndInvoke($ui.Async) } catch { Write-SdLog ('Skan: ' + $_.Exception.Message) 'ERROR' }
    try { if ($ui.Ps.Streams.Error.Count -gt 0) { Write-SdLog ('Błędy runspace: ' + $ui.Ps.Streams.Error[0].ToString()) 'WARN' } } catch { }
    try { $ui.Ps.Dispose(); $ui.Rs.Close(); $ui.Rs.Dispose() } catch { }
    $ui.Scanning = $false
    if (-not $ui.Ctx.Finished) { $ui.Ctx.Finished = Get-Date }
    if ($ui.Ctx.Findings.Count -eq 0) {
        $tail = (@($ui.Ctx.Log.ToArray() | Select-Object -Last 6) -join "`n")
        [void](Show-SdMessage ("Skanowanie nie zwróciło żadnych wyników - prawdopodobnie nie udało się załadować modułów testów.`n`n" + $tail) 'SerwisDiag' 'Warning')
    }
    $c.Prog.Value = $c.Prog.Maximum
    $c.BtnStart.IsEnabled = $true; $c.BtnCancel.IsEnabled = $false
    $c.ProgText.Text = $(if ($ui.CancelRequested) { 'Diagnostykę przerwano - zapisano wyniki częściowe.' } else { 'Diagnostyka zakończona.' })
    try {
        $res = Get-SdResult
        $ui.Result = $res
        $dir = Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings
        $ui.ReportPaths = Save-SdReports -Result $res -Settings $ui.Settings -OutDir $dir
        Set-SdUiResultButtons $true
        $c.FooterText.Text = ('Raporty zapisano w: ' + $dir)
        if ($ui.Settings.AutoPdf -and -not $ui.SelfTest) {
            $c.ProgText.Text = 'Zapisywanie PDF dla klienta...'
            $pdf = ConvertTo-SdPdf -HtmlPath $ui.ReportPaths['Customer']
            if ($pdf.Ok) { $ui.ReportPaths['CustomerPdf'] = $pdf.Path } else { $c.FooterText.Text = 'Raporty zapisano w: ' + $dir + ' (PDF: ' + $pdf.Error + ')' }
            $c.ProgText.Text = $(if ($ui.CancelRequested) { 'Diagnostykę przerwano - zapisano wyniki częściowe.' } else { 'Diagnostyka zakończona.' })
        }
    } catch {
        Write-SdLog ('Zapis raportów: ' + $_.Exception.Message) 'ERROR'
        $c.FooterText.Text = 'Nie udało się zapisać raportów: ' + $_.Exception.Message
    }
    Refresh-SdUiPage
    $open = [string]$ui.Settings.OpenAfterScan
    if (($open -eq 'customer' -or $open -eq 'technical') -and $ui.ReportPaths -and -not $ui.SelfTest -and -not $ui.CancelRequested) {
        $key = $(if ($open -eq 'technical') { 'Technical' } else { 'Customer' })
        try { Start-Process -FilePath $ui.ReportPaths[$key] } catch { }
    }
    if ($ui.OnScanComplete) { & $ui.OnScanComplete }
}

# ------------------------------------------------------------------ narzędzia serwisowe

function Get-SdUiTools {
    # Uwaga: skrypty akcji nie są domknięciami - nie mogą korzystać ze zmiennych lokalnych tej funkcji.
    return @(
        @{ G = 'Narzędzia systemowe'; T = 'Menedżer urządzeń'; D = 'Sterowniki i urządzenia (devmgmt.msc)'; A = { Start-Process 'devmgmt.msc' } }
        @{ G = 'Narzędzia systemowe'; T = 'Zarządzanie dyskami'; D = 'Partycje i woluminy (diskmgmt.msc)'; A = { Start-Process 'diskmgmt.msc' } }
        @{ G = 'Narzędzia systemowe'; T = 'Podgląd zdarzeń'; D = 'Dzienniki systemu (eventvwr.msc)'; A = { Start-Process 'eventvwr.msc' } }
        @{ G = 'Narzędzia systemowe'; T = 'Monitor niezawodności'; D = 'Historia awarii i indeks stabilności (perfmon /rel)'; A = { Start-Process 'perfmon.exe' -ArgumentList '/rel' } }
        @{ G = 'Narzędzia systemowe'; T = 'Monitor zasobów'; D = 'Procesor, pamięć, dysk, sieć w czasie rzeczywistym'; A = { Start-Process 'resmon.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'Menedżer zadań'; D = 'Procesy i autostart'; A = { Start-Process 'taskmgr.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'Usługi'; D = 'services.msc'; A = { Start-Process 'services.msc' } }
        @{ G = 'Narzędzia systemowe'; T = 'Konfiguracja systemu'; D = 'msconfig - rozruch i usługi'; A = { Start-Process 'msconfig.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'Informacje o systemie'; D = 'msinfo32'; A = { Start-Process 'msinfo32.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'DirectX / grafika'; D = 'dxdiag'; A = { Start-Process 'dxdiag.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'Programy i funkcje'; D = 'Odinstalowywanie programów (appwiz.cpl)'; A = { Start-Process 'appwiz.cpl' } }
        @{ G = 'Narzędzia systemowe'; T = 'Połączenia sieciowe'; D = 'ncpa.cpl'; A = { Start-Process 'ncpa.cpl' } }
        @{ G = 'Narzędzia systemowe'; T = 'Windows Update'; D = 'Ustawienia aktualizacji'; A = { try { Start-Process 'ms-settings:windowsupdate' } catch { Start-Process 'control.exe' -ArgumentList '/name Microsoft.WindowsUpdate' } } }
        @{ G = 'Narzędzia systemowe'; T = 'Oczyszczanie dysku'; D = 'cleanmgr'; A = { Start-Process 'cleanmgr.exe' } }
        @{ G = 'Narzędzia systemowe'; T = 'Optymalizacja dysków'; D = 'defrag / TRIM (dfrgui)'; A = { Start-Process 'dfrgui.exe' } }
        @{ G = 'Diagnostyka'; T = 'Diagnostyka pamięci Windows'; D = 'Test RAM po ponownym uruchomieniu komputera (mdsched). Wynik pojawi się przy następnej diagnostyce w kategorii Awarie i zdarzenia.'; Confirm = 'Uruchomić Diagnostykę pamięci Windows? Komputer zostanie ponownie uruchomiony, jeśli wybierzesz restart.'; A = { Start-Process 'mdsched.exe' } }
        @{ G = 'Diagnostyka'; T = 'Raport baterii'; D = 'powercfg /batteryreport - historia i pojemność baterii'; A = { $p = Join-Path $global:SdUi.ReportDir 'raport-baterii.html'; [void](Invoke-Native -File (Join-Path ([Environment]::GetFolderPath('System')) 'powercfg.exe') -Arguments ('/batteryreport /output "{0}"' -f $p) -TimeoutSec 60); if (Test-Path -LiteralPath $p) { Start-Process $p } } }
        @{ G = 'Diagnostyka'; T = 'Raport energetyczny (60 s)'; D = 'powercfg /energy - problemy z zasilaniem i usypianiem'; Admin = $true; Confirm = 'Raport energetyczny zbiera dane przez 60 sekund. Uruchomić?'; A = { Start-Process 'cmd.exe' -ArgumentList ('/k powercfg /energy /output "{0}" /duration 60 & start "" "{0}"' -f (Join-Path $global:SdUi.ReportDir 'raport-energii.html')) } }
        @{ G = 'Diagnostyka'; T = 'Test ekranu (martwe piksele)'; D = 'Pełnoekranowe kolory do wykrywania uszkodzonych pikseli i smug'; A = { Show-SdScreenTest } }
        @{ G = 'Diagnostyka'; T = 'Test klawiatury'; D = 'Sprawdza działanie wszystkich klawiszy'; A = { Show-SdKeyboardTest } }
        @{ G = 'Sterowniki'; T = 'Sterowniki z Windows Update'; D = 'Wyszukuje oficjalne, podpisane sterowniki dla urządzeń tego komputera i instaluje zaznaczone (internet; instalacja wymaga administratora)'; A = { Show-SdUiDrivers } }
        @{ G = 'Sterowniki'; T = 'Brakujące sterowniki (Katalog Microsoft)'; D = 'Urządzenia z błędami i wyszukiwanie ich sterowników w Katalogu Microsoft Update po identyfikatorze sprzętu'; A = { Show-SdUiMissingDrivers } }
        @{ G = 'Sterowniki'; T = 'Strona sterowników producenta'; D = 'Otwiera stronę ze sterownikami producenta komputera (albo płyty głównej) i kopiuje do schowka numer seryjny lub model do wpisania'; A = { Invoke-SdUiVendorPage } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'Kontrola plików systemowych (SFC)'; D = 'sfc /scannow - sprawdza i naprawia uszkodzone pliki systemowe (10-20 min)'; Admin = $true; Confirm = 'Uruchomić sfc /scannow? Operacja trwa 10-20 minut i może naprawiać pliki systemowe.'; A = { Start-Process 'cmd.exe' -ArgumentList '/k sfc /scannow' } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'DISM RestoreHealth (z internetu)'; D = 'Naprawa magazynu składników Windows plikami pobranymi z Windows Update - wymaga internetu'; Admin = $true; Confirm = 'Uruchomić DISM /Online /Cleanup-Image /RestoreHealth? Pliki naprawcze zostaną pobrane z Windows Update; operacja może trwać kilkanaście minut.'; A = { Start-Process 'cmd.exe' -ArgumentList '/k DISM /Online /Cleanup-Image /RestoreHealth' } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'DISM RestoreHealth z płyty/ISO'; D = 'Naprawa bez internetu: pliki z obrazu ISO albo nośnika instalacyjnego (install.wim / install.esd) tej samej wersji Windows'; Admin = $true; A = { Invoke-SdUiDismFromMedia } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'CHKDSK - skan online (tylko odczyt)'; D = 'chkdsk /scan - sprawdza system plików bez blokowania dysku'; Admin = $true; A = { Start-Process 'cmd.exe' -ArgumentList ('/k chkdsk {0} /scan' -f $env:SystemDrive) } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'Zaplanuj CHKDSK przy starcie'; D = 'Oznacza wolumin systemowy jako wymagający sprawdzenia (fsutil dirty set); chkdsk uruchomi się po restarcie'; Admin = $true; Confirm = 'Zaplanować sprawdzanie dysku systemowego przy następnym uruchomieniu? Na dysku z objawami awarii najpierw skopiuj dane.'; A = { Start-Process 'cmd.exe' -ArgumentList ('/k fsutil dirty set {0} & echo. & echo Sprawdzanie dysku uruchomi sie po ponownym starcie komputera.' -f $env:SystemDrive) } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'Reset komponentów Windows Update'; D = 'Zatrzymuje usługi, zmienia nazwę SoftwareDistribution i catroot2, uruchamia usługi'; Admin = $true; Confirm = 'Zresetować komponenty Windows Update? Foldery pamięci podręcznej aktualizacji zostaną zmienione na .old.'; A = { Start-Process 'cmd.exe' -ArgumentList '/k net stop wuauserv & net stop cryptSvc & net stop bits & net stop msiserver & rmdir /s /q %SystemRoot%\SoftwareDistribution.old 2>nul & rmdir /s /q %SystemRoot%\System32\catroot2.old 2>nul & ren %SystemRoot%\SoftwareDistribution SoftwareDistribution.old & ren %SystemRoot%\System32\catroot2 catroot2.old & net start wuauserv & net start cryptSvc & net start bits & net start msiserver & echo. & echo Gotowe - uruchom ponownie komputer.' } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'Wyczyść DNS'; D = 'ipconfig /flushdns'; A = { Start-Process 'cmd.exe' -ArgumentList '/k ipconfig /flushdns' } }
        @{ G = 'Naprawa (uruchamia okno konsoli)'; T = 'Reset Winsock i TCP/IP'; D = 'netsh winsock reset oraz netsh int ip reset - naprawa problemów z siecią (wymaga restartu)'; Admin = $true; Confirm = 'Zresetować Winsock i stos TCP/IP? Wymagane będzie ponowne uruchomienie komputera.'; A = { Start-Process 'cmd.exe' -ArgumentList '/k netsh winsock reset & netsh int ip reset & ipconfig /flushdns & echo. & echo Gotowe - uruchom ponownie komputer.' } }
        @{ G = 'Konserwacja'; T = 'Utwórz punkt przywracania'; D = 'Punkt przywracania przed zmianami (system zezwala zwykle na jeden na 24 h)'; Admin = $true; A = { try { Checkpoint-Computer -Description 'SerwisDiag - przed zmianami' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; [void](Show-SdMessage 'Punkt przywracania został utworzony.' 'SerwisDiag' 'Information') } catch { [void](Show-SdMessage ('Nie udało się utworzyć punktu przywracania:' + "`n" + $_.Exception.Message + "`n`nSprawdź, czy ochrona systemu jest włączona dla dysku systemowego.") 'SerwisDiag' 'Warning') } } }
        @{ G = 'Konserwacja'; T = 'Cofnij naprawy z dziennika'; D = 'Przywraca ustawienia zmienione przez naprawy programu: rejestr, typ uruchamiania usług, zaporę, SMB1'; A = { Show-SdUiUndo } }
        @{ G = 'Konserwacja'; T = 'Kopia przed reinstalacją Windows'; D = 'Sterowniki, lista programów, klucz Windows i dane systemu (opcjonalnie profile Wi-Fi i klucze BitLocker) w folderze, np. na pendrive'; A = { Show-SdUiBackup } }
        @{ G = 'Konserwacja'; T = 'Wyczyść pliki tymczasowe'; D = 'Usuwa zawartość folderów Temp użytkownika i systemu (poza plikami używanymi)'; Confirm = 'Usunąć pliki tymczasowe (Temp użytkownika i Windows\Temp)? Pliki używane przez programy zostaną pominięte.'; A = { $before = 0.0; $after = 0.0; $dirs = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')); foreach ($d in $dirs) { $before += (Get-SdDirSize $d).Bytes }; foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }; foreach ($d in $dirs) { $after += (Get-SdDirSize $d).Bytes }; [void](Show-SdMessage ('Zwolniono: ' + (Format-Size ($before - $after) 1)) 'SerwisDiag' 'Information') } }
    )
}

function Initialize-SdUiTools {
    $ui = $global:SdUi; $c = $ui.C
    $tools = Get-SdUiTools
    $groups = [ordered]@{}
    foreach ($t in $tools) {
        if (-not $groups.Contains($t.G)) { $groups[$t.G] = New-Object System.Collections.ArrayList }
        [void]$groups[$t.G].Add($t)
    }
    $note = New-Object System.Windows.Controls.TextBlock
    $note.Text = 'Narzędzia otwierają odpowiednie okna systemu Windows lub konsolę. Operacje oznaczone jako naprawcze zmieniają system - wykonuj je świadomie, najlepiej po kopii danych i punkcie przywracania. Część wymaga uprawnień administratora.'
    $note.TextWrapping = 'Wrap'; $note.Foreground = Get-SdBrush '#667085'; $note.Margin = New-Object System.Windows.Thickness(4, 2, 4, 10)
    [void]$c.ToolsPanel.Children.Add($note)
    foreach ($g in $groups.Keys) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = Get-SdBrush '#FFFFFF'; $card.BorderBrush = Get-SdBrush '#E4E7EC'; $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(12); $card.Padding = New-Object System.Windows.Thickness(18, 14, 18, 8); $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
        $sp = New-Object System.Windows.Controls.StackPanel
        $h = New-Object System.Windows.Controls.TextBlock
        $h.Text = $g; $h.FontWeight = [System.Windows.FontWeights]::SemiBold; $h.FontSize = 15; $h.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
        [void]$sp.Children.Add($h)
        $wp = New-Object System.Windows.Controls.WrapPanel
        foreach ($t in $groups[$g]) {
            $b = New-Object System.Windows.Controls.Button
            $b.Content = $t.T
            $b.ToolTip = $t.D + $(if ($t.Admin) { ' (wymaga administratora)' } else { '' })
            $b.Tag = $t
            $b.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
            $b.Add_Click({ param($s, $e) Invoke-SdUiTool $s.Tag })
            [void]$wp.Children.Add($b)
        }
        [void]$sp.Children.Add($wp)
        $card.Child = $sp
        [void]$c.ToolsPanel.Children.Add($card)
    }
}

function Invoke-SdUiTool {
    param($Tool)
    $ui = $global:SdUi
    if ($Tool.Admin -and -not (Test-SdAdmin)) {
        [void](Show-SdMessage 'Ta operacja wymaga uprawnień administratora. Uruchom program jako administrator.' 'Wymagane uprawnienia' 'Warning')
        return
    }
    if ($Tool.Confirm) {
        if ((Show-SdMessage $Tool.Confirm 'Potwierdzenie' 'Question' 'YesNo') -ne 'Yes') { return }
    }
    try { & $Tool.A } catch { [void](Show-SdMessage ('Nie udało się uruchomić: ' + $_.Exception.Message) 'Błąd' 'Error') }
}

# ------------------------------------------------------------------ ustawienia

function Show-SdUiSettings {
    $ui = $global:SdUi
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiSettingsXaml)
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'SShop', 'SPhone', 'SMail', 'SAddr', 'STech', 'SLogo', 'SLogoBtn', 'SDir', 'SDirBtn', 'SOpen', 'SPdf', 'SUpd', 'SMon', 'SMonInt', 'SSave', 'SCancel') { $n[$name] = $w.FindName($name) }
    $s = $ui.Settings
    $n.SShop.Text = [string]$s.ShopName; $n.SPhone.Text = [string]$s.ShopPhone; $n.SMail.Text = [string]$s.ShopEmail; $n.SAddr.Text = [string]$s.ShopAddress
    $n.STech.Text = [string]$s.Technician; $n.SLogo.Text = [string]$s.LogoPath; $n.SDir.Text = [string]$s.ReportDir
    $n.SOpen.SelectedIndex = [math]::Max(@('none', 'customer', 'technical').IndexOf([string]$s.OpenAfterScan), 0)
    $n.SPdf.IsChecked = [bool]$s.AutoPdf
    # aktualizacje i monitorowanie dotyczą wersji zainstalowanej; przenośna (pendrive) niczego nie zostawia na komputerze klienta
    $installed = [bool](Get-SdInstallMode $ui.Root)
    $n.SUpd.IsChecked = [bool]$s.AutoUpdateCheck
    foreach ($iv in $global:SdMonitorIntervals) { [void]$n.SMonInt.Items.Add((Get-SdMonitorIntervalText $iv)) }
    $mst = Read-SdMonitorState
    $n.SMonInt.SelectedIndex = [math]::Max([array]::IndexOf($global:SdMonitorIntervals, $(if ($mst) { $mst.Interval } else { 60 })), 0)
    $monWas = $false
    if ($installed) { $monWas = [bool](Get-SdMonitorAutostart) }
    $n.SMon.IsChecked = $monWas
    if (-not $installed) {
        foreach ($cb in $n.SUpd, $n.SMon, $n.SMonInt) { $cb.IsEnabled = $false; $cb.ToolTip = 'Dostępne w wersji zainstalowanej (instalator SerwisDiag-<wersja>-setup.exe).' }
    }
    $n.SLogoBtn.Add_Click({
            $d = New-Object Microsoft.Win32.OpenFileDialog
            $d.Filter = 'Obrazy (*.png;*.jpg;*.jpeg;*.svg;*.gif)|*.png;*.jpg;*.jpeg;*.svg;*.gif'
            if ($d.ShowDialog()) { $n.SLogo.Text = $d.FileName }
        }.GetNewClosure())
    $n.SDirBtn.Add_Click({
            Add-Type -AssemblyName System.Windows.Forms
            $d = New-Object System.Windows.Forms.FolderBrowserDialog
            if ($d.ShowDialog() -eq 'OK') { $n.SDir.Text = $d.SelectedPath }
        }.GetNewClosure())
    $ui.TestWindow = $w
    $n.SSave.Add_Click({
            $s2 = $global:SdUi.Settings
            $s2.ShopName = $n.SShop.Text.Trim(); $s2.ShopPhone = $n.SPhone.Text.Trim(); $s2.ShopEmail = $n.SMail.Text.Trim(); $s2.ShopAddress = $n.SAddr.Text.Trim()
            $s2.Technician = $n.STech.Text.Trim(); $s2.LogoPath = $n.SLogo.Text.Trim(); $s2.ReportDir = $n.SDir.Text.Trim()
            $s2.OpenAfterScan = @('none', 'customer', 'technical')[[math]::Max($n.SOpen.SelectedIndex, 0)]
            $s2.AutoPdf = [bool]$n.SPdf.IsChecked
            $s2.AutoUpdateCheck = [bool]$n.SUpd.IsChecked
            try { Save-SdSettings -Root $global:SdUi.Root -Settings $s2 } catch { [void](Show-SdMessage ('Nie udało się zapisać ustawień: ' + $_.Exception.Message) 'Błąd' 'Error') }
            if ($installed) {
                $root = $global:SdUi.Root
                try { Set-SdMonitorInterval -Minutes $global:SdMonitorIntervals[[math]::Max($n.SMonInt.SelectedIndex, 0)] } catch { }
                $monNow = [bool]$n.SMon.IsChecked
                if ($monNow -ne $monWas) {
                    try {
                        if ($monNow) { [void](Register-SdMonitorAutostart -Root $root); [void](Stop-SdMonitorProcess); Start-SdMonitorProcess -Root $root }
                        else { [void](Stop-SdMonitorProcess); [void](Unregister-SdMonitorAutostart) }
                    } catch { [void](Show-SdMessage ('Nie udało się zmienić monitorowania: ' + $_.Exception.Message) 'Błąd' 'Error') }
                }
            }
            $w.DialogResult = $true
        }.GetNewClosure())
    [void]$w.ShowDialog()
    Update-SdUiHeader
}

function Show-SdUiCompare {
    # Okno porównania: podpowiada raport bieżącej diagnostyki jako "po" i poprzedni raport tego komputera jako "przed".
    $ui = $global:SdUi
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiCompareXaml)
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'CBefore', 'CBeforeBtn', 'CAfter', 'CAfterBtn', 'CWork', 'CMake', 'CCancel') { $n[$name] = $w.FindName($name) }
    $dir = Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings
    $ticket = $ui.C.TxtTicket.Text.Trim()
    $after = ''
    if ($ui.ReportPaths -and $ui.ReportPaths['Json']) { $after = [string]$ui.ReportPaths['Json'] }
    else { $after = Find-SdReportJson -Dir $dir -ComputerName $env:COMPUTERNAME -Ticket $ticket }
    $n.CAfter.Text = $after
    $n.CBefore.Text = Find-SdReportJson -Dir $dir -ComputerName $env:COMPUTERNAME -Ticket $ticket -Exclude @($after)
    if ($ui.LastRepair) { $n.CWork.Text = Get-SdRepairWorkText $ui.LastRepair }
    $pick = {
        param($box, [string]$startDir)
        $d = New-Object Microsoft.Win32.OpenFileDialog
        $d.Filter = 'Raport SerwisDiag (*.json)|*.json'
        $cur = $box.Text.Trim()
        if ($cur -and (Test-Path -LiteralPath $cur)) { $d.InitialDirectory = Split-Path -Parent $cur }
        elseif ($startDir -and (Test-Path -LiteralPath $startDir)) { $d.InitialDirectory = $startDir }
        if ($d.ShowDialog()) { $box.Text = $d.FileName }
    }
    $n.CBeforeBtn.Add_Click({ & $pick $n.CBefore $dir }.GetNewClosure())
    $n.CAfterBtn.Add_Click({ & $pick $n.CAfter $dir }.GetNewClosure())
    $state = @{ Paths = $null; Summary = ''; Error = '' }
    $n.CMake.Add_Click({
            $bp = $n.CBefore.Text.Trim(); $ap = $n.CAfter.Text.Trim()
            if (-not $bp -or -not $ap) { [void][System.Windows.MessageBox]::Show($w, 'Wskaż oba raporty JSON: sprzed naprawy i po naprawie.', 'Porównanie', 'OK', 'Information'); return }
            try {
                $cmp = New-SdComparison -Before (Import-SdReportJson $bp) -After (Import-SdReportJson $ap) -WorkDone $n.CWork.Text.Trim()
                $state.Paths = Save-SdComparisonReports -Comparison $cmp -Settings $global:SdUi.Settings -OutDir (Split-Path -Parent $ap)
                $state.Summary = Get-SdComparisonSummaryText $cmp.Counts
                if (@($cmp.Notes).Count -gt 0) { $state.Summary += "`n`nUwagi:`n" + (@($cmp.Notes) -join "`n") }
                $w.DialogResult = $true
            } catch {
                [void][System.Windows.MessageBox]::Show($w, ('Nie udało się utworzyć porównania:' + "`n" + $_.Exception.Message), 'Porównanie', 'OK', 'Error')
            }
        }.GetNewClosure())
    $ui.TestWindow = $w
    [void]$w.ShowDialog()
    if ($state.Paths) {
        $ui.C.FooterText.Text = 'Porównanie zapisano w: ' + (Split-Path -Parent $state.Paths['Customer'])
        $ans = Show-SdMessage ('Utworzono raport z naprawy (' + $state.Summary + ").`n`nOtworzyć wersję dla klienta?") 'Porównanie' 'Question' 'YesNo'
        if ($ans -eq 'Yes') { try { Start-Process -FilePath $state.Paths['Customer'] } catch { } }
    }
}

# ------------------------------------------------------------------ zadania w tle okien (runspace okna)

function New-SdUiTaskPs {
    # Polecenie PowerShell ze skryptem i parametrami w runspace okna (uruchamia je wywołujący).
    # Parametry przez GetEnumerator(): przy kluczu „Keys” zapis $Params.Keys zwraca wartość tego klucza zamiast listy kluczy.
    param($Runspace, [string]$Script, [hashtable]$Params = @{})
    $ps = [powershell]::Create()
    $ps.Runspace = $Runspace
    [void]$ps.AddScript($Script)
    foreach ($kv in $Params.GetEnumerator()) { [void]$ps.AddParameter([string]$kv.Key, $kv.Value) }
    return $ps
}

# ------------------------------------------------------------------ sterowniki

function Start-SdUiDriverTask {
    # Zadanie w tle okna sterowników w stałym runspace okna: wynik wyszukiwania zostaje w tym runspace,
    # więc instalacja używa tych samych obiektów Windows Update. Do runspace przekazujemy tekst skryptu.
    param([string]$Phase, [string]$Script, [hashtable]$Params = @{})
    $d = $global:SdUi.DrvDlg
    $ps = New-SdUiTaskPs -Runspace $d.Rs -Script $Script -Params $Params
    $d.Phase = $Phase; $d.Ps = $ps; $d.Busy = $true
    $d.N.DProg.Visibility = 'Visible'
    $d.N.DInstall.IsEnabled = $false; $d.N.DSearch.IsEnabled = $false
    $d.Async = $ps.BeginInvoke()
}

function Complete-SdUiDriverTask {
    $d = $global:SdUi.DrvDlg
    $n = $d.N
    $out = $null
    try { $out = @($d.Ps.EndInvoke($d.Async)) | Select-Object -Last 1 } catch { $out = [pscustomobject]@{ Error = $_.Exception.Message } }
    try { $d.Ps.Dispose() } catch { }
    $d.Busy = $false
    $n.DProg.Visibility = 'Collapsed'
    $n.DSearch.IsEnabled = $true
    switch ($d.Phase) {
        'search' {
            $n.DList.Children.Clear()
            $d.Items = @()
            if (-not $out -or $out.Error) {
                $n.DStatus.Text = 'Nie udało się wyszukać sterowników: ' + $(if ($out) { $out.Error } else { 'brak wyniku' }) + "`nSprawdź połączenie z internetem i usługę Windows Update."
                return
            }
            $d.Items = @($out.Items)
            if ($d.Items.Count -eq 0) { $n.DStatus.Text = 'Windows Update nie ma nowszych sterowników dla urządzeń tego komputera.'; return }
            $def = @(Select-SdDriversToInstall $d.Items | ForEach-Object { $_.UpdateId })
            foreach ($it in ($d.Items | Sort-Object @{ Expression = { if ([int]$_.DeviceProblem -ne 0) { 0 } else { 1 } } }, Class, Title)) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 6)
                $cb.Tag = $it.UpdateId
                $cb.IsChecked = ($def -contains $it.UpdateId)
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.TextWrapping = 'Wrap'
                $r1 = New-Object System.Windows.Documents.Run($it.Title)
                $r1.FontWeight = [System.Windows.FontWeights]::SemiBold
                [void]$tb.Inlines.Add($r1)
                [void]$tb.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
                $info = Join-NonEmpty @($it.Class, ('wersja z ' + (Format-Dt $it.Date -DateOnly)), (Format-Size $it.SizeBytes 1), $(if ([int]$it.DeviceProblem -ne 0) { 'naprawia urządzenie z błędem (kod ' + $it.DeviceProblem + ')' }), $(if ($it.Optional) { 'opcjonalny' })) ' · '
                $r2 = New-Object System.Windows.Documents.Run($info)
                $r2.Foreground = Get-SdBrush '#667085'; $r2.FontSize = 12
                [void]$tb.Inlines.Add($r2)
                $cb.Content = $tb
                [void]$n.DList.Children.Add($cb)
            }
            $n.DStatus.Text = ('Znaleziono: {0}.' -f (Format-Count $d.Items.Count 'sterownik' 'sterowniki' 'sterowników'))
            if (-not (Test-SdAdmin)) { $n.DStatus.Text += ' Instalacja wymaga uprawnień administratora - użyj „Uruchom jako administrator” w oknie programu.' }
            else { $n.DInstall.IsEnabled = $true }
        }
        'restore' {
            if ($out -and $out.Ok) { Start-SdUiDriverInstall; return }
            $msg = 'Nie udało się utworzyć punktu przywracania:' + "`n" + $(if ($out) { $out.Error } else { 'brak wyniku' }) + "`n`nZainstalować sterowniki bez punktu przywracania?"
            if ([string][System.Windows.MessageBox]::Show($d.W, $msg, 'Punkt przywracania', 'YesNo', 'Warning') -eq 'Yes') { Start-SdUiDriverInstall; return }
            $n.DStatus.Text = 'Instalację anulowano.'
            $n.DInstall.IsEnabled = $true
        }
        'install' {
            $d.Installed = $true
            $lines = @()
            if ($out -and $out.Error) { $lines += ('Błąd: ' + $out.Error) }
            if ($out) { foreach ($x in @($out.Results)) { $lines += ('{0} - {1}' -f (Get-SdWuResultText $x.ResultCode), $x.Title) } }
            $ok = @($out.Results | Where-Object { $_.ResultCode -eq 2 }).Count
            $head = 'Instalacja zakończona: {0} z {1}.' -f $ok, @($out.Results).Count
            if ($out -and $out.RebootRequired) { $head += ' Wymagane ponowne uruchomienie komputera.' }
            $n.DStatus.Text = $head + "`n" + ($lines -join "`n")
            $n.DList.Children.Clear()
            $global:SdUi.C.FooterText.Text = 'Sterowniki z Windows Update: ' + $head
            if ($out -and $out.RebootRequired) { [void][System.Windows.MessageBox]::Show($d.W, ($head + "`n`nUruchom komputer ponownie, a potem wykonaj diagnostykę jeszcze raz."), 'Sterowniki', 'OK', 'Information') }
        }
    }
}

function Start-SdUiDriverInstall {
    $d = $global:SdUi.DrvDlg
    $d.N.DStatus.Text = 'Pobieranie i instalowanie sterowników... nie zamykaj okna.'
    Start-SdUiDriverTask -Phase 'install' -Script $global:SdWuDriverInstall.ToString() -Params @{ UpdateIds = [string[]]$d.Selected; Status = $d.State }
}

function Show-SdUiDrivers {
    $ui = $global:SdUi
    if ([bool]$ui.C.ChkOffline.IsChecked) {
        [void](Show-SdMessage 'Włączony jest tryb bez internetu. Wyszukiwanie sterowników wymaga internetu - odznacz „tryb bez internetu”.' 'Sterowniki' 'Information')
        return
    }
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiDriversXaml)))
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'DList', 'DRestore', 'DStatus', 'DProg', 'DSearch', 'DInstall', 'DClose') { $n[$name] = $w.FindName($name) }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.Open()
    $d = @{ W = $w; N = $n; Rs = $rs; Ps = $null; Async = $null; Phase = ''; Busy = $false; Items = @(); Selected = @(); Installed = $false
        State = [hashtable]::Synchronized(@{ Text = '' }) }
    $ui.DrvDlg = $d
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
            $dd = $global:SdUi.DrvDlg
            if (-not $dd -or -not $dd.Busy) { return }
            if ($dd.Phase -eq 'install' -and $dd.State['Text']) { $dd.N.DStatus.Text = [string]$dd.State['Text'] + ' Nie zamykaj okna.' }
            if ($dd.Async -and $dd.Async.IsCompleted) { Complete-SdUiDriverTask }
        })
    $d.Timer = $timer
    $search = {
        $dd = $global:SdUi.DrvDlg
        $dd.N.DList.Children.Clear()
        $dd.N.DStatus.Text = 'Wyszukiwanie sterowników w Windows Update (zwykle kilkanaście sekund)...'
        Start-SdUiDriverTask -Phase 'search' -Script $global:SdWuDriverSearch.ToString() -Params @{ KeepResult = $true }
    }
    $n.DSearch.Add_Click($search)
    $n.DInstall.Add_Click({
            $dd = $global:SdUi.DrvDlg
            $ids = @($dd.N.DList.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
            if ($ids.Count -eq 0) { [void][System.Windows.MessageBox]::Show($dd.W, 'Zaznacz sterowniki do zainstalowania.', 'Sterowniki', 'OK', 'Information'); return }
            $size = 0.0
            foreach ($it in $dd.Items) { if ($ids -contains $it.UpdateId) { $size += [double]$it.SizeBytes } }
            $q = 'Zainstalować {0} (do pobrania ok. {1})?' -f (Format-Count $ids.Count 'sterownik' 'sterowniki' 'sterowników'), (Format-Size $size 1)
            if ($dd.N.DRestore.IsChecked) { $q += "`n`nNajpierw zostanie utworzony punkt przywracania systemu." }
            $q += "`n`nPodczas instalacji ekran może na chwilę zgasnąć, a połączenie sieciowe zostać przerwane."
            if ([string][System.Windows.MessageBox]::Show($dd.W, $q, 'Instalacja sterowników', 'YesNo', 'Question') -ne 'Yes') { return }
            $dd.Selected = $ids
            if ($dd.N.DRestore.IsChecked) {
                $dd.N.DStatus.Text = 'Tworzenie punktu przywracania (może potrwać minutę)...'
                $rp = 'param($Status) try { Checkpoint-Computer -Description ''SerwisDiag - przed instalacją sterowników'' -RestorePointType DEVICE_DRIVER_INSTALL -ErrorAction Stop; [pscustomobject]@{ Ok = $true; Error = '''' } } catch { [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message } }'
                Start-SdUiDriverTask -Phase 'restore' -Script $rp -Params @{ Status = $dd.State }
            } else { Start-SdUiDriverInstall }
        })
    $w.Add_Closing({
            param($s, $e)
            $dd = $global:SdUi.DrvDlg
            if ($dd.Busy -and $dd.Phase -ne 'search') {
                $e.Cancel = $true
                [void][System.Windows.MessageBox]::Show($dd.W, 'Trwa tworzenie punktu przywracania lub instalacja sterowników - poczekaj na zakończenie.', 'Sterowniki', 'OK', 'Information')
            }
        })
    $w.Add_ContentRendered($search)
    $ui.TestWindow = $w
    $timer.Start()
    [void]$w.ShowDialog()
    $timer.Stop()
    # trwające wyszukiwanie przerywamy w tle - zamykanie runspace czekałoby na odpowiedź Windows Update
    if ($d.Busy -and $d.Ps) { try { [void]$d.Ps.BeginStop($null, $null) } catch { } }
    else { try { $rs.Dispose() } catch { } }
    $ui.DrvDlg = $null
}

function Show-SdUiMissingDrivers {
    $ui = $global:SdUi
    $devs = @(Get-Cim Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' | Where-Object { [int]$_.ConfigManagerErrorCode -ne 22 })
    if ($devs.Count -eq 0) {
        [void](Show-SdMessage 'Wszystkie urządzenia mają sterowniki i działają poprawnie (Menedżer urządzeń nie zgłasza błędów).' 'Brakujące sterowniki' 'Information')
        return
    }
    $rows = @($devs | Sort-Object @{ Expression = { if ([int]$_.ConfigManagerErrorCode -eq 28) { 0 } else { 1 } } }, Name | ForEach-Object {
            $hw = ''
            if ($_.HardwareID) { $hw = [string](@($_.HardwareID)[0]) } elseif ($_.PNPDeviceID) { $hw = [string]$_.PNPDeviceID }
            [pscustomobject]@{
                Urządzenie = $(if ($_.Name) { [string]$_.Name } else { 'Nieznane urządzenie' }); Kod = [int]$_.ConfigManagerErrorCode
                Problem = (Get-SdPnpErrorText ([int]$_.ConfigManagerErrorCode)); Producent = (Get-SdVendorName $hw); Identyfikator = $hw
            }
        })
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiMissingXaml)))
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $grid = $w.FindName('MGrid')
    $grid.ItemsSource = (ConvertTo-SdDataTable ([pscustomobject]@{ Columns = @('Urządzenie', 'Kod', 'Problem', 'Producent', 'Identyfikator'); Rows = $rows })).DefaultView
    $grid.SelectedIndex = 0
    $ui.MissDlg = @{ W = $w; Grid = $grid }
    $getId = { $g = $global:SdUi.MissDlg.Grid; if ($g.SelectedItem) { [string]$g.SelectedItem.Row['Identyfikator'] } else { '' } }
    $w.FindName('MCatalog').Add_Click({
            $id = & $getId
            if (-not $id) { return }
            try { Start-Process (Get-SdCatalogUrl $id) } catch { [void](Show-SdMessage ('Nie udało się otworzyć przeglądarki: ' + $_.Exception.Message) 'Błąd' 'Error') }
        }.GetNewClosure())
    $w.FindName('MCopy').Add_Click({
            $id = & $getId
            if ($id) { try { [System.Windows.Clipboard]::SetText($id) } catch { } }
        }.GetNewClosure())
    $w.FindName('MVendor').Add_Click({ Invoke-SdUiVendorPage })
    $ui.TestWindow = $w
    [void]$w.ShowDialog()
    $ui.MissDlg = $null
}

function Invoke-SdUiVendorPage {
    if (Test-SdVm) {
        [void](Show-SdMessage 'To maszyna wirtualna - sterowniki dostarcza platforma wirtualizacji (np. Hyper-V, VMware Tools, VirtualBox Guest Additions).' 'Strona producenta' 'Information')
        return
    }
    $info = Get-SdComputerSupportInfo
    if ($info.CopyText) { try { [System.Windows.Clipboard]::SetText([string]$info.CopyText) } catch { } }
    if ($info.IsSearch) { $msg = 'Nie rozpoznano producenta komputera - otwieram wyszukiwarkę sterowników dla: ' + $info.Vendor + '.' }
    else { $msg = 'Otwieram stronę ze sterownikami: ' + $info.Vendor + $(if ($info.Board) { ' (producent płyty głównej - komputer składany)' } else { '' }) + '.' }
    if ($info.CopyText) { $msg += "`n`nDo schowka skopiowano " + $info.CopyLabel + ': ' + $info.CopyText + "`nWklej go (Ctrl+V) w polu wyszukiwania na stronie producenta." }
    [void](Show-SdMessage $msg 'Strona producenta' 'Information')
    try { Start-Process $info.Url } catch { [void](Show-SdMessage ('Nie udało się otworzyć przeglądarki: ' + $_.Exception.Message) 'Błąd' 'Error') }
}

function Invoke-SdUiDismFromMedia {
    # DISM RestoreHealth bez internetu: pliki naprawcze z obrazu ISO albo nośnika instalacyjnego tej samej wersji Windows.
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Wskaż obraz ISO Windows albo plik install.wim / install.esd (folder sources na nośniku instalacyjnym)'
    $dlg.Filter = 'Obraz Windows (*.iso;*.wim;*.esd)|*.iso;*.wim;*.esd'
    if (-not $dlg.ShowDialog()) { return }
    $img = $null; $sel = $null
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        $img = Resolve-SdInstallImage $dlg.FileName
        if (-not $img.Error) {
            $w = Get-SdWinInfo
            $eds = @(Get-SdImageEditions $img.ImagePath)
            $sel = Select-SdImageIndex -Images $eds -EditionId $w.Edition -Build $w.Build -Arch $w.Arch -Language ([System.Globalization.CultureInfo]::InstalledUICulture.Name)
        }
    } catch {
        $img = [pscustomobject]@{ ImagePath = ''; MountedIso = ''; Error = ('Nie udało się odczytać obrazu: ' + $_.Exception.Message) }
    } finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    if ($img.Error) { [void](Show-SdMessage $img.Error 'DISM z płyty/ISO' 'Warning'); return }
    if (-not $sel -or $sel.Index -le 0) {
        $why = $(if ($sel) { $sel.Problems -join "`n" } else { 'brak danych o obrazie' })
        if ($img.MountedIso) { try { Dismount-DiskImage -ImagePath $img.MountedIso -ErrorAction Stop | Out-Null } catch { } }
        [void](Show-SdMessage ("Ten obraz nie nadaje się do naprawy tego systemu:`n" + $why) 'DISM z płyty/ISO' 'Warning')
        return
    }
    $msg = 'Uruchomić naprawę magazynu składników z obrazu?' + "`n`nObraz: " + $img.ImagePath + "`nEdycja: " + $sel.Image.Name + ' (indeks ' + $sel.Index + ', kompilacja ' + $sel.Image.Build + ')'
    if (@($sel.Problems).Count -gt 0) { $msg += "`n`nUwagi:`n" + (@($sel.Problems) -join "`n") }
    $msg += "`n`nNaprawa trwa zwykle kilkanaście minut i nie korzysta z internetu."
    if ((Show-SdMessage $msg 'DISM z płyty/ISO' 'Question' 'YesNo') -ne 'Yes') { return }
    $src = Get-SdDismSourceArg -ImagePath $img.ImagePath -Index $sel.Index
    $tail = ''
    if ($img.MountedIso) { $tail = ' & echo. & echo Po zakonczeniu mozna odlaczyc obraz ISO: Eksplorator, prawy przycisk na napedzie - Wysun.' }
    Start-Process 'cmd.exe' -ArgumentList ('/k DISM /Online /Cleanup-Image /RestoreHealth ' + $src + ' /LimitAccess' + $tail)
}

# ------------------------------------------------------------------ naprawa problemów po diagnostyce

# Skrypty wykonywane w osobnym runspace okna napraw (program ładuje się tam raz - wykrywanie i naprawy działają w tle).
$global:SdUiFixScripts = @{
    Detect  = @'
param($Root, $Result, $IsAdmin, $Offline)
if (-not $global:SdFixLoaded) { $SdRoot = $Root; . (Join-Path $Root 'lib\Load.ps1'); $global:SdFixLoaded = $true }
$global:SD = New-SdContext -Root $Root -Offline:$Offline
$c = Get-SdFixCandidates -Context @{ Result = $Result; IsAdmin = $IsAdmin; Offline = $Offline }
$global:SdFixCandidates = $c
[pscustomobject]@{ Candidates = @($c); Unfixed = @(Get-SdUnfixedProblems -Result $Result -Candidates $c) }
'@
    Restore = @'
param($FixKeys, $Status)
$out = [pscustomobject]@{ Ok = $false; Error = ''; Pre = @() }
$pre = @($global:SdFixCandidates | Where-Object { $FixKeys -contains $_.Key -and $_.FixId -eq 'fx.restoreon' })
if ($pre.Count -gt 0) { $out.Pre = @(Invoke-SdFixes -Candidates $pre -Status $Status) }
$Status['Text'] = 'Tworzenie punktu przywracania (może potrwać minutę)...'
try { New-SdRepairRestorePoint; $out.Ok = $true } catch { $out.Error = $_.Exception.Message }
$out
'@
    Fix     = @'
param($FixKeys, $Status, $Exclude)
$sel = @($global:SdFixCandidates | Where-Object { $FixKeys -contains $_.Key -and @($Exclude) -notcontains $_.Key })
[pscustomobject]@{ Results = @(Invoke-SdFixes -Candidates $sel -Status $Status) }
'@
}

function New-SdUiFixDialog {
    # Okno napraw (jeszcze niepokazane) z runspace na pracę w tle i stanem okna; zdarzenia podpina Show-SdUiFixes.
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiFixesXaml)))
    $n = @{}
    foreach ($name in 'FList', 'FRestore', 'FStatus', 'FProg', 'FRecommended', 'FNone', 'FRun', 'FRescan', 'FClose') { $n[$name] = $w.FindName($name) }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.Open()
    return @{ W = $w; N = $n; Rs = $rs; Ps = $null; Async = $null; Phase = ''; Busy = $false; Candidates = @(); Boxes = @(); FixKeys = @(); Done = @(); PreResults = @(); Results = @()
        State = [hashtable]::Synchronized(@{ Index = 0; Total = 0; Text = '' }) }
}

function Start-SdUiFixTask {
    param([string]$Phase, [string]$Script, [hashtable]$Params = @{})
    $d = $global:SdUi.FixDlg
    $ps = New-SdUiTaskPs -Runspace $d.Rs -Script $Script -Params $Params
    $d.Phase = $Phase; $d.Ps = $ps; $d.Busy = $true
    $n = $d.N
    $n.FProg.Visibility = 'Visible'
    $n.FProg.IsIndeterminate = ($Phase -ne 'fix')
    $n.FRun.IsEnabled = $false; $n.FRecommended.IsEnabled = $false; $n.FNone.IsEnabled = $false; $n.FRestore.IsEnabled = $false
    $d.Async = $ps.BeginInvoke()
}

function Start-SdUiFixSelected {
    # Wybrane i potwierdzone naprawy: najpierw (opcjonalnie) punkt przywracania, potem naprawy - wszystko w tle.
    param([string[]]$FixKeys, [bool]$Restore)
    $d = $global:SdUi.FixDlg
    $d.FixKeys = $FixKeys; $d.Done = @(); $d.PreResults = @()
    if ($Restore) {
        $d.N.FStatus.Text = 'Przygotowanie punktu przywracania...'
        Start-SdUiFixTask -Phase 'restore' -Script $global:SdUiFixScripts.Restore -Params @{ FixKeys = $FixKeys; Status = $d.State }
    } else { Start-SdUiFixRun }
}

function Start-SdUiFixRun {
    $d = $global:SdUi.FixDlg
    $d.N.FStatus.Text = 'Naprawianie... nie zamykaj okna i nie wyłączaj komputera.'
    Start-SdUiFixTask -Phase 'fix' -Script $global:SdUiFixScripts.Fix -Params @{ FixKeys = [string[]]$d.FixKeys; Status = $d.State; Exclude = [string[]]@($d.Done) }
}

function Add-SdUiFixText {
    # Akapit na liście okna napraw: fragmenty { T = tekst; B = pogrubienie; C = kolor; S = rozmiar; NL = nowy wiersz przed }.
    param($Panel, [object[]]$Parts, [string]$Margin = '0,2,0,2', [string]$ToolTip = '')
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.Margin = (New-Object System.Windows.ThicknessConverter).ConvertFromInvariantString($Margin)   # w pl-PL przecinek to separator dziesiętny
    if ($ToolTip) { $tb.ToolTip = $ToolTip }
    foreach ($p in $Parts) {
        if ($p.NL) { [void]$tb.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
        $r = New-Object System.Windows.Documents.Run([string]$p.T)
        if ($p.B) { $r.FontWeight = [System.Windows.FontWeights]::SemiBold }
        if ($p.C) { $r.Foreground = Get-SdBrush $p.C }
        if ($p.S) { $r.FontSize = [double]$p.S }
        [void]$tb.Inlines.Add($r)
    }
    if ($Panel) { [void]$Panel.Children.Add($tb) }
    return $tb
}

function Complete-SdUiFixTask {
    $ui = $global:SdUi
    $d = $ui.FixDlg
    $n = $d.N
    $out = $null
    try { $out = @($d.Ps.EndInvoke($d.Async)) | Select-Object -Last 1 } catch { $out = [pscustomobject]@{ Error = $_.Exception.Message } }
    # błąd pojedynczego polecenia skryptu nie przerywa EndInvoke - bez odczytu strumienia błędów zginąłby bez śladu
    $errs = @()
    try { $errs = @($d.Ps.Streams.Error | ForEach-Object { [string]$_ }) } catch { }
    foreach ($e in $errs) { Write-SdLog ('Okno napraw (' + $d.Phase + '): ' + $e) 'ERROR' }
    try { $d.Ps.Dispose() } catch { }
    $d.Busy = $false
    $n.FProg.Visibility = 'Collapsed'
    switch ($d.Phase) {
        'detect' {
            $n.FList.Children.Clear()
            if (-not $out -or ($out.PSObject.Properties['Error'] -and $out.Error)) {
                $n.FStatus.Text = 'Nie udało się sprawdzić, co można naprawić: ' + $(if ($out) { $out.Error } else { 'brak wyniku' })
                return
            }
            $d.Candidates = @($out.Candidates)
            $d.Boxes = @()
            if ($d.Candidates.Count -eq 0) {
                [void](Add-SdUiFixText $n.FList @(@{ T = 'Program nie znalazł problemów, które może naprawić sam.'; B = $true }))
            }
            $group = ''
            foreach ($c in ($d.Candidates | Sort-Object Order)) {
                if ($c.Group -ne $group) {
                    $group = $c.Group
                    [void](Add-SdUiFixText $n.FList @(@{ T = $group; B = $true; C = '#0F6CBD'; S = 14 }) $(if ($n.FList.Children.Count -gt 0) { '0,12,0,2' } else { '0,0,0,2' }))
                }
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 8)
                $cb.Tag = $c.Key
                $cb.IsChecked = [bool]$c.Default
                $cb.IsEnabled = -not $c.Blocked
                $badges = @()
                if ($c.Reboot) { $badges += 'wymaga ponownego uruchomienia' }
                if ($c.Long) { $badges += 'potrwa kilkanaście minut' }
                if ($c.Interactive) { $badges += 'otworzy okno deinstalatora' }
                if ($c.Risk -eq 'medium') { $badges += 'ryzyko: średnie' } elseif ($c.Risk -eq 'high') { $badges += 'ryzyko: wysokie' }
                if ($c.NeedsInternet) { $badges += 'wymaga internetu' }
                $parts = @(@{ T = $c.Title; B = $true })
                if ($c.Problem) { $parts += @{ T = $c.Problem; C = '#475467'; NL = $true } }
                $parts += @{ T = ('Co zrobi: ' + $c.Description + $(if ($badges.Count) { ' · ' + ($badges -join ' · ') } else { '' })); C = '#667085'; S = 12; NL = $true }
                if ($c.Blocked) { $parts += @{ T = 'Niedostępne: ' + $c.Blocked; C = '#B42318'; S = 12; NL = $true } }
                $cb.Content = (Add-SdUiFixText $null $parts '0')
                [void]$n.FList.Children.Add($cb)
                $d.Boxes += $cb
            }
            $uf = @($out.Unfixed)
            if ($uf.Count -gt 0) {
                [void](Add-SdUiFixText $n.FList @(@{ T = 'Tego program nie naprawi - wymaga pracy serwisanta'; B = $true; C = '#B54708'; S = 14 }) '0,14,0,2')
                foreach ($f in ($uf | Select-Object -First 25)) {
                    [void](Add-SdUiFixText $n.FList @(@{ T = '• ' + $f.Title + ': '; B = $true; C = '#344054' }, @{ T = [string]$f.Value; C = '#475467' }) '0,2,0,2' ([string]$f.Advice))
                }
            }
            $enabled = @($d.Boxes | Where-Object { $_.IsEnabled }).Count
            $txt = 'Program może naprawić: {0}' -f (Format-Count $d.Candidates.Count 'problem' 'problemy' 'problemów')
            if ($enabled -lt $d.Candidates.Count) { $txt += ' (część wymaga uprawnień administratora lub internetu - użyj „Uruchom jako administrator”)' }
            $n.FStatus.Text = $txt + '.'
            $n.FRun.IsEnabled = ($enabled -gt 0); $n.FRecommended.IsEnabled = ($enabled -gt 0); $n.FNone.IsEnabled = ($enabled -gt 0); $n.FRestore.IsEnabled = ($enabled -gt 0)
        }
        'restore' {
            $d.PreResults = @()
            if ($out -and $out.PSObject.Properties['Pre']) { $d.PreResults = @($out.Pre) }
            if ($d.PreResults.Count -gt 0) { $d.Done = @($d.Candidates | Where-Object { $d.FixKeys -contains $_.Key -and $_.FixId -eq 'fx.restoreon' } | ForEach-Object { $_.Key }) }
            if ($out -and $out.Ok) { Start-SdUiFixRun; return }
            $msg = 'Nie udało się utworzyć punktu przywracania:' + "`n" + $(if ($out) { $out.Error } else { 'brak wyniku' }) + "`n`nWykonać naprawy bez punktu przywracania? (Zmiany i tak zostaną zapisane w dzienniku napraw.)"
            if ([string][System.Windows.MessageBox]::Show($d.W, $msg, 'Punkt przywracania', 'YesNo', 'Warning') -eq 'Yes') { Start-SdUiFixRun; return }
            $n.FStatus.Text = 'Naprawy anulowano.'
            $n.FRun.IsEnabled = $true; $n.FRecommended.IsEnabled = $true; $n.FNone.IsEnabled = $true; $n.FRestore.IsEnabled = $true
        }
        'fix' {
            $all = @($d.PreResults)
            if ($out -and $out.PSObject.Properties['Results']) { $all += @($out.Results) }
            $lost = @($d.FixKeys).Count - $all.Count
            if ($out -and $out.PSObject.Properties['Error'] -and $out.Error) { $all += [pscustomobject]@{ Title = 'Naprawy'; CustomerTitle = ''; FixId = ''; Result = 'error'; Message = $out.Error; Reboot = $false; Changes = @() } }
            elseif ($lost -gt 0) {
                # każda zaznaczona naprawa daje wynik - brakujące to błąd programu, a nie „wykonano 0 z 0”
                $msg = 'Program nie wykonał {0} (błąd programu){1}.' -f (Format-Count $lost 'zaznaczonej naprawy' 'zaznaczonych napraw' 'zaznaczonych napraw'), $(if ($errs.Count) { ': ' + $errs[0] } else { '' })
                $all += [pscustomobject]@{ Title = 'Naprawy'; CustomerTitle = ''; FixId = ''; Result = 'error'; Message = $msg; Reboot = $false; Changes = @() }
            }
            $d.Results = $all
            $n.FList.Children.Clear()
            [void](Add-SdUiFixText $n.FList @(@{ T = 'Wynik napraw'; B = $true; C = '#0F6CBD'; S = 14 }) '0,0,0,4')
            $labels = @{ ok = @('OK', '#067647'); warn = @('UWAGA', '#B54708'); error = @('BŁĄD', '#B42318'); skip = @('POMINIĘTO', '#667085') }
            foreach ($r in $all) {
                $lb = $labels[[string]$r.Result]
                if (-not $lb) { $lb = @([string]$r.Result, '#475467') }
                $parts = @(@{ T = '[' + $lb[0] + '] '; B = $true; C = $lb[1] }, @{ T = $r.Title; B = $true })
                if ($r.Message) { $parts += @{ T = $r.Message; C = '#475467'; NL = $true } }
                [void](Add-SdUiFixText $n.FList $parts '0,4,0,4')
            }
            $path = ''
            try { $path = Save-SdRepairLog -Results $all -Meta $ui.Result.Meta -OutDir (Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings) } catch { Write-SdLog ('Dziennik napraw: ' + $_.Exception.Message) 'ERROR' }
            $ui.LastRepair = $all
            $okN = @($all | Where-Object { $_.Result -eq 'ok' -or $_.Result -eq 'warn' }).Count
            $errN = @($all | Where-Object { $_.Result -eq 'error' }).Count
            $reboot = (@($all | Where-Object { $_.Reboot -and $_.Result -ne 'error' -and $_.Result -ne 'skip' }).Count -gt 0)
            $head = 'Zakończono: wykonano {0} z {1}{2}.' -f $okN, $all.Count, $(if ($errN) { ', nieudane: ' + $errN } else { '' })
            if ($reboot) { $head += ' Część napraw zadziała po ponownym uruchomieniu komputera.' }
            if ($path) { $head += "`nDziennik napraw: " + $path; $ui.C.FooterText.Text = 'Dziennik napraw: ' + $path }
            $head += "`n" + 'Sprawdź efekt: diagnostyka ponownie, a potem „Porównaj przed/po” (wykonane naprawy wpiszą się same).'
            $n.FStatus.Text = $head
            $n.FRun.Visibility = 'Collapsed'; $n.FRecommended.Visibility = 'Collapsed'; $n.FNone.Visibility = 'Collapsed'
            $n.FRescan.Visibility = 'Visible'
            if ($reboot) { [void][System.Windows.MessageBox]::Show($d.W, 'Część napraw zadziała dopiero po ponownym uruchomieniu komputera. Uruchom go ponownie, a potem wykonaj diagnostykę i porównanie przed/po.', 'Naprawa', 'OK', 'Information') }
        }
    }
}

function Show-SdUiFixes {
    $ui = $global:SdUi
    if (-not $ui.Result) { [void](Show-SdMessage 'Najpierw wykonaj diagnostykę - naprawy dobierane są do jej wyników.' 'Naprawa' 'Information'); return }
    $d = New-SdUiFixDialog
    $w = $d.W; $n = $d.N; $rs = $d.Rs
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $ui.FixDlg = $d
    $ui.RescanAfterFix = $false
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
            $dd = $global:SdUi.FixDlg
            if (-not $dd -or -not $dd.Busy) { return }
            $st = $dd.State
            if ($dd.Phase -eq 'fix' -and [int]$st['Total'] -gt 0) {
                $dd.N.FProg.Value = 100.0 * ([int]$st['Index'] - 1) / [int]$st['Total']
                if ($st['Text']) { $dd.N.FStatus.Text = ('[{0}/{1}] {2}... nie zamykaj okna.' -f $st['Index'], $st['Total'], $st['Text']) }
            } elseif ($dd.Phase -eq 'restore' -and $st['Text']) { $dd.N.FStatus.Text = [string]$st['Text'] }
            if ($dd.Async -and $dd.Async.IsCompleted) { Complete-SdUiFixTask }
        })
    $d.Timer = $timer
    $n.FRecommended.Add_Click({
            $dd = $global:SdUi.FixDlg
            foreach ($cb in $dd.Boxes) { if ($cb.IsEnabled) { $k = [string]$cb.Tag; $cb.IsChecked = (@($dd.Candidates | Where-Object { $_.Key -eq $k -and $_.Default }).Count -gt 0) } }
        })
    $n.FNone.Add_Click({ foreach ($cb in $global:SdUi.FixDlg.Boxes) { $cb.IsChecked = $false } })
    $n.FRun.Add_Click({
            $dd = $global:SdUi.FixDlg
            $keys = @($dd.Boxes | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object { [string]$_.Tag })
            if ($keys.Count -eq 0) { [void][System.Windows.MessageBox]::Show($dd.W, 'Zaznacz naprawy do wykonania.', 'Naprawa', 'OK', 'Information'); return }
            $sel = @($dd.Candidates | Where-Object { $keys -contains $_.Key })
            $q = 'Wykonać {0}?' -f (Format-Count $keys.Count 'naprawę' 'naprawy' 'napraw')
            if ($dd.N.FRestore.IsChecked) { $q += "`n`nNajpierw zostanie utworzony punkt przywracania systemu." }
            if (@($sel | Where-Object { $_.Long }).Count) { $q += "`nCzęść napraw (DISM, SFC, sterowniki) potrwa kilkanaście minut - nie wyłączaj komputera." }
            if (@($sel | Where-Object { $_.Interactive }).Count) { $q += "`nDeinstalatory programów otworzą własne okna - przejdź je ręcznie." }
            if (@($sel | Where-Object { $_.Reboot }).Count) { $q += "`nCzęść zmian zadziała po ponownym uruchomieniu komputera." }
            $q += "`n`nProgram jest udostępniany bez gwarancji - naprawy wykonujesz na własną odpowiedzialność."
            if ([string][System.Windows.MessageBox]::Show($dd.W, $q, 'Naprawa', 'YesNo', 'Question') -ne 'Yes') { return }
            Start-SdUiFixSelected -FixKeys $keys -Restore ([bool]$dd.N.FRestore.IsChecked)
        })
    $n.FRescan.Add_Click({ $global:SdUi.RescanAfterFix = $true; $global:SdUi.FixDlg.W.Close() })
    $w.Add_Closing({
            param($s, $e)
            $dd = $global:SdUi.FixDlg
            if ($dd.Busy -and $dd.Phase -ne 'detect') {
                $e.Cancel = $true
                [void][System.Windows.MessageBox]::Show($dd.W, 'Trwa naprawa - poczekaj na jej zakończenie.', 'Naprawa', 'OK', 'Information')
            }
        })
    $w.Add_ContentRendered({
            $dd = $global:SdUi.FixDlg
            $dd.N.FStatus.Text = 'Sprawdzanie, co można naprawić...'
            Start-SdUiFixTask -Phase 'detect' -Script $global:SdUiFixScripts.Detect -Params @{ Root = $global:SdUi.Root; Result = $global:SdUi.Result; IsAdmin = (Test-SdAdmin); Offline = [bool]$global:SdUi.C.ChkOffline.IsChecked }
        })
    $ui.TestWindow = $w
    $timer.Start()
    [void]$w.ShowDialog()
    $timer.Stop()
    if ($d.Busy -and $d.Ps) { try { [void]$d.Ps.BeginStop($null, $null) } catch { } }
    else { try { $rs.Dispose() } catch { } }
    $ui.FixDlg = $null
    if ($ui.RescanAfterFix) { Start-SdUiScan }
}

# ------------------------------------------------------------------ PDF i raport anonimowy

function Invoke-SdUiPdf {
    # Raport dla klienta jako PDF (obok raportu HTML) i otwarcie pliku.
    $ui = $global:SdUi
    if (-not $ui.ReportPaths) { return }
    $pdfPath = [string]$ui.ReportPaths['CustomerPdf']
    if (-not $pdfPath -or -not (Test-Path -LiteralPath $pdfPath)) {
        $ui.C.FooterText.Text = 'Zapisywanie PDF...'
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        try { $r = ConvertTo-SdPdf -HtmlPath $ui.ReportPaths['Customer'] } finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
        if (-not $r.Ok) {
            $ui.C.FooterText.Text = 'Nie udało się zapisać PDF.'
            [void](Show-SdMessage ('Nie udało się zapisać raportu jako PDF:' + "`n" + $r.Error) 'Zapisz PDF' 'Warning')
            return
        }
        $pdfPath = $r.Path
        $ui.ReportPaths['CustomerPdf'] = $pdfPath
    }
    $ui.C.FooterText.Text = 'PDF dla klienta: ' + $pdfPath
    try { Start-Process -FilePath $pdfPath } catch { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $pdfPath) }
}

function Invoke-SdUiAnonymous {
    # Raport anonimowy obok pozostałych raportów; podsumowanie tekstowe trafia do schowka (do wklejenia w poście).
    $ui = $global:SdUi
    if (-not $ui.Result) { return }
    $dir = Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try { $p = Save-SdAnonymousReports -Result $ui.Result -OutDir $dir }
    catch { [System.Windows.Input.Mouse]::OverrideCursor = $null; [void](Show-SdMessage ('Nie udało się zapisać raportu anonimowego: ' + $_.Exception.Message) 'Raport anonimowy' 'Error'); return }
    finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    $copied = $false
    try { [System.Windows.Clipboard]::SetText([System.IO.File]::ReadAllText($p.Text, [System.Text.Encoding]::UTF8)); $copied = $true } catch { }
    $ui.C.FooterText.Text = 'Raport anonimowy: ' + $p.Html
    $msg = 'Zapisano raport anonimowy - bez nazwy komputera i kont, numerów seryjnych, kluczy, adresów IP/MAC, nazw sieci Wi-Fi i danych klienta:' + "`n" + $p.Html
    if ($copied) { $msg += "`n`nKrótkie podsumowanie skopiowano do schowka - możesz je wkleić w poście na forum." }
    $msg += "`n`nPrzed publikacją przejrzyj raport: program usuwa znane dane identyfikujące, ale nie gwarantuje, że wykryje wszystkie."
    [void](Show-SdMessage $msg 'Raport anonimowy' 'Information')
    try { Start-Process -FilePath $p.Html } catch { }
}

# ------------------------------------------------------------------ kopia przed reinstalacją Windows

$global:SdUiBackupScript = @'
param($Root, $Dest, $Include, $Status)
if (-not $global:SdBkLoaded) { $SdRoot = $Root; . (Join-Path $Root 'lib\Load.ps1'); $global:SdBkLoaded = $true }
$global:SD = New-SdContext -Root $Root
try { Invoke-SdBackup -Dest $Dest -Include $Include -Status $Status }
catch { [pscustomobject]@{ Dir = ''; Parts = @(); Warnings = @(); Error = $_.Exception.Message } }
'@

function Complete-SdUiBackup {
    $d = $global:SdUi.BackupDlg
    $n = $d.N
    $out = $null
    try { $out = @($d.Ps.EndInvoke($d.Async)) | Select-Object -Last 1 } catch { $out = [pscustomobject]@{ Dir = ''; Parts = @(); Warnings = @(); Error = $_.Exception.Message } }
    try { $d.Ps.Dispose() } catch { }
    $d.Busy = $false
    $n.BProg.Visibility = 'Collapsed'
    $n.BClose.IsEnabled = $true
    if (-not $out -or ($out.PSObject.Properties['Error'] -and $out.Error) -or -not $out.Dir) {
        $n.BStatus.Text = 'Nie udało się utworzyć kopii: ' + $(if ($out -and $out.PSObject.Properties['Error']) { $out.Error } else { 'brak wyniku' })
        $n.BRun.IsEnabled = $true
        return
    }
    $d.Dir = [string]$out.Dir
    $n.BList.Children.Clear()
    [void](Add-SdUiFixText $n.BList @(@{ T = 'Wynik kopii'; B = $true; C = '#0F6CBD'; S = 14 }) '0,0,0,4')
    $labels = @{ ok = @('OK', '#067647'); warn = @('UWAGA', '#B54708'); skip = @('POMINIĘTO', '#667085'); error = @('BŁĄD', '#B42318') }
    foreach ($p in @($out.Parts)) {
        $lb = $labels[[string]$p.Result]
        if (-not $lb) { $lb = @([string]$p.Result, '#475467') }
        [void](Add-SdUiFixText $n.BList @(@{ T = '[' + $lb[0] + '] '; B = $true; C = $lb[1] }, @{ T = $p.Label; B = $true }, @{ T = $p.Message; C = '#475467'; NL = $true }) '0,4,0,4')
    }
    foreach ($wn in @($out.Warnings)) { [void](Add-SdUiFixText $n.BList @(@{ T = 'Uwaga: '; B = $true; C = '#B54708' }, @{ T = $wn; C = '#7A2E0E' }) '0,8,0,2') }
    $n.BStatus.Text = 'Kopię zapisano w: ' + $d.Dir + "`nInstrukcja przywracania jest w pliku CZYTAJ.txt w tym folderze."
    $n.BOpen.Visibility = 'Visible'
    $global:SdUi.C.FooterText.Text = 'Kopia przed reinstalacją: ' + $d.Dir
}

function Show-SdUiBackup {
    $ui = $global:SdUi
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiBackupXaml)))
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'BList', 'BPick', 'BDest', 'BStatus', 'BProg', 'BOpen', 'BRun', 'BClose') { $n[$name] = $w.FindName($name) }
    $isAdmin = Test-SdAdmin
    $boxes = @()
    foreach ($p in $global:SdBackupParts) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 8)
        $cb.Tag = $p.Key
        $cb.IsChecked = [bool]$p.Default
        $parts = @(@{ T = $p.Label; B = $true }, @{ T = $p.Description; C = '#667085'; S = 12; NL = $true })
        if ($p.Admin -and -not $isAdmin) {
            $parts += @{ T = 'Wymaga uprawnień administratora - użyj „Uruchom jako administrator” w oknie programu.'; C = '#B42318'; S = 12; NL = $true }
            $cb.IsEnabled = $false; $cb.IsChecked = $false
        }
        $cb.Content = (Add-SdUiFixText $null $parts '0')
        [void]$n.BList.Children.Add($cb)
        $boxes += $cb
    }
    $n.BDest.Text = Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.Open()
    $d = @{ W = $w; N = $n; Rs = $rs; Ps = $null; Async = $null; Busy = $false; Boxes = $boxes; Dir = ''; State = [hashtable]::Synchronized(@{ Text = '' }) }
    $ui.BackupDlg = $d
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
            $dd = $global:SdUi.BackupDlg
            if (-not $dd -or -not $dd.Busy) { return }
            if ($dd.State['Text']) { $dd.N.BStatus.Text = [string]$dd.State['Text'] + ' Nie zamykaj okna.' }
            if ($dd.Async -and $dd.Async.IsCompleted) { Complete-SdUiBackup }
        })
    $n.BPick.Add_Click({
            $dd = $global:SdUi.BackupDlg
            Add-Type -AssemblyName System.Windows.Forms
            $fd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fd.Description = 'Folder na kopię (najlepiej pendrive albo dysk inny niż systemowy)'
            if ($dd.N.BDest.Text -and (Test-Path -LiteralPath $dd.N.BDest.Text)) { $fd.SelectedPath = $dd.N.BDest.Text }
            if ($fd.ShowDialog() -eq 'OK') { $dd.N.BDest.Text = $fd.SelectedPath }
        })
    $n.BOpen.Add_Click({ $dd = $global:SdUi.BackupDlg; if ($dd.Dir) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dd.Dir) } })
    $n.BRun.Add_Click({
            $dd = $global:SdUi.BackupDlg
            $inc = @($dd.Boxes | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object { [string]$_.Tag })
            $dest = $dd.N.BDest.Text.Trim()
            if ($inc.Count -eq 0) { [void][System.Windows.MessageBox]::Show($dd.W, 'Zaznacz, co ma znaleźć się w kopii.', 'Kopia', 'OK', 'Information'); return }
            if (-not $dest) { [void][System.Windows.MessageBox]::Show($dd.W, 'Wskaż folder docelowy kopii.', 'Kopia', 'OK', 'Information'); return }
            $q = @()
            $root = [System.IO.Path]::GetPathRoot($dest)
            if ($root -and $root.TrimEnd('\').ToUpper() -eq ([string]$env:SystemDrive).ToUpper()) { $q += 'Folder jest na dysku systemowym - przy reinstalacji zostanie usunięty. Po utworzeniu kopii przenieś ją na pendrive.' }
            if ($inc -contains 'wifi' -or $inc -contains 'bitlocker') { $q += 'Kopia będzie zawierać ' + $(if ($inc -contains 'wifi') { 'hasła Wi-Fi' } else { '' }) + $(if ($inc -contains 'wifi' -and $inc -contains 'bitlocker') { ' i ' } else { '' }) + $(if ($inc -contains 'bitlocker') { 'klucze odzyskiwania BitLocker' } else { '' }) + ' zapisane jawnym tekstem.' }
            if ($inc -contains 'drivers') {
                # za długa ścieżka przerwałaby eksport sterowników w połowie - lepiej od razu wybrać krótszy folder
                [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                try { $lc = Test-SdDriverExport -DriverDir (Join-Path (Join-Path $dest (Get-SdBackupDirName)) 'sterowniki') } finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
                if (-not $lc.Ok) { [void][System.Windows.MessageBox]::Show($dd.W, ('Sterowniki nie zmieszczą się w tym folderze - ' + $lc.Message), 'Kopia', 'OK', 'Warning'); return }
            }
            if ($q.Count -gt 0 -and [string][System.Windows.MessageBox]::Show($dd.W, (($q -join "`n`n") + "`n`nKontynuować?"), 'Kopia', 'YesNo', 'Question') -ne 'Yes') { return }
            $dd.Busy = $true
            $dd.N.BRun.IsEnabled = $false; $dd.N.BClose.IsEnabled = $false
            $dd.N.BProg.Visibility = 'Visible'
            $dd.N.BStatus.Text = 'Tworzenie kopii...'
            $ps = [powershell]::Create()
            $ps.Runspace = $dd.Rs
            [void]$ps.AddScript($global:SdUiBackupScript)
            [void]$ps.AddParameter('Root', $global:SdUi.Root); [void]$ps.AddParameter('Dest', $dest); [void]$ps.AddParameter('Include', [string[]]$inc); [void]$ps.AddParameter('Status', $dd.State)
            $dd.Ps = $ps
            $dd.Async = $ps.BeginInvoke()
        })
    $w.Add_Closing({
            param($s, $e)
            $dd = $global:SdUi.BackupDlg
            if ($dd.Busy) { $e.Cancel = $true; [void][System.Windows.MessageBox]::Show($dd.W, 'Trwa tworzenie kopii - poczekaj na zakończenie.', 'Kopia', 'OK', 'Information') }
        })
    $ui.TestWindow = $w
    $timer.Start()
    [void]$w.ShowDialog()
    $timer.Stop()
    try { $rs.Dispose() } catch { }
    $ui.BackupDlg = $null
}

# ------------------------------------------------------------------ cofanie napraw

function Update-SdUiUndoList {
    # Wczytuje dziennik napraw do okna cofania: pola wyboru dla zmian ustawień, lista operacji bez cofania.
    param([string]$Path)
    $d = $global:SdUi.UndoDlg
    $n = $d.N
    $n.UList.Children.Clear(); $d.Boxes = @(); $d.Items = @(); $d.Path = ''
    $n.URun.IsEnabled = $false
    $n.UFile.Text = $Path
    if (-not $Path) {
        [void](Add-SdUiFixText $n.UList @(@{ T = 'Brak dziennika napraw tego komputera w folderze raportów.'; B = $true }, @{ T = 'Dziennik powstaje po wykonaniu napraw w programie (plik *_naprawy.json). Wskaż go przyciskiem „Wybierz dziennik...”.'; C = '#667085'; NL = $true }))
        $n.UStatus.Text = ''
        return
    }
    $log = $null
    try { $log = Read-SdRepairJson $Path } catch { $n.UStatus.Text = 'Nie udało się odczytać dziennika: ' + $_.Exception.Message; return }
    if ([string]$log.computer -ne $env:COMPUTERNAME) {
        $n.UStatus.Text = ('Ten dziennik pochodzi z innego komputera ({0}) - jego zmian nie można cofnąć tutaj.' -f $log.computer)
        return
    }
    $d.Path = $Path
    $d.Items = @(Get-SdUndoItems $log)
    $when = ''
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse([string]$log.created, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { $when = Format-Dt $dt }
    [void](Add-SdUiFixText $n.UList @(@{ T = ('Naprawy z ' + $when + $(if ($log.ticket) { ', zlecenie ' + $log.ticket } else { '' })); B = $true; C = '#0F6CBD'; S = 14 }) '0,0,0,6')
    if ($d.Items.Count -eq 0) { [void](Add-SdUiFixText $n.UList @(@{ T = 'W tym dzienniku nie ma zmian ustawień do cofnięcia.'; C = '#475467' })) }
    foreach ($it in $d.Items) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 6)
        $cb.IsChecked = $true
        $cb.Tag = $it
        $cb.Content = (Add-SdUiFixText $null @(@{ T = $it.FixTitle; B = $true }, @{ T = $it.Text; C = '#475467'; S = 12; NL = $true }) '0')
        [void]$n.UList.Children.Add($cb)
        $d.Boxes += $cb
    }
    $nu = @(Get-SdNotUndoable $log)
    if ($nu.Count -gt 0) {
        [void](Add-SdUiFixText $n.UList @(@{ T = 'Bez cofania przez program (użyj punktu przywracania, jeśli trzeba)'; B = $true; C = '#B54708'; S = 14 }) '0,14,0,2')
        foreach ($t in $nu) { [void](Add-SdUiFixText $n.UList @(@{ T = '• ' + $t; C = '#475467' })) }
    }
    $n.URun.IsEnabled = ($d.Items.Count -gt 0)
    $n.UStatus.Text = ('Zmian do cofnięcia: {0}.' -f $d.Items.Count) + $(if (-not (Test-SdAdmin)) { ' Cofanie wymaga uprawnień administratora - użyj „Uruchom jako administrator” w oknie programu.' } else { '' })
}

function Show-SdUiUndo {
    $ui = $global:SdUi
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiUndoXaml)))
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'UPick', 'UFile', 'UList', 'UStatus', 'URestore', 'URun', 'UClose') { $n[$name] = $w.FindName($name) }
    $ui.UndoDlg = @{ W = $w; N = $n; Path = ''; Items = @(); Boxes = @() }
    $dir = Resolve-SdReportDir -Root $ui.Root -Settings $ui.Settings
    Update-SdUiUndoList (@(Find-SdRepairJson -Dir $dir) | Select-Object -First 1)
    $n.UPick.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Dziennik napraw SerwisDiag (*_naprawy.json)|*_naprawy.json|JSON (*.json)|*.json'
            $dlg.InitialDirectory = Resolve-SdReportDir -Root $global:SdUi.Root -Settings $global:SdUi.Settings
            if ($dlg.ShowDialog()) { Update-SdUiUndoList $dlg.FileName }
        })
    $n.URestore.Add_Click({ try { Start-Process 'rstrui.exe' } catch { [void][System.Windows.MessageBox]::Show($global:SdUi.UndoDlg.W, ('Nie udało się uruchomić przywracania systemu: ' + $_.Exception.Message), 'Cofanie napraw', 'OK', 'Error') } })
    $n.URun.Add_Click({
            $d = $global:SdUi.UndoDlg
            if (-not (Test-SdAdmin)) { [void][System.Windows.MessageBox]::Show($d.W, 'Cofanie zmian wymaga uprawnień administratora. Uruchom program jako administrator.', 'Cofanie napraw', 'OK', 'Warning'); return }
            $sel = @($d.Boxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
            if ($sel.Count -eq 0) { [void][System.Windows.MessageBox]::Show($d.W, 'Zaznacz zmiany do cofnięcia.', 'Cofanie napraw', 'OK', 'Information'); return }
            $q = ('Cofnąć {0}?' -f (Format-Count $sel.Count 'zmianę' 'zmiany' 'zmian')) + "`n`nPrzywrócone zostaną ustawienia sprzed naprawy - także te niebezpieczne (np. wyłączona zapora albo przekierowanie programu dodane przez złośliwe oprogramowanie)."
            if ([string][System.Windows.MessageBox]::Show($d.W, $q, 'Cofanie napraw', 'YesNo', 'Question') -ne 'Yes') { return }
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
            $res = @()
            try { $res = @(Invoke-SdUndo $sel) } finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
            $logPath = ''
            try { $logPath = Save-SdUndoLog -Results $res -RepairJsonPath $d.Path } catch { Write-SdLog ('Dziennik cofnięcia: ' + $_.Exception.Message) 'ERROR' }
            $n2 = $d.N
            $n2.UList.Children.Clear()
            [void](Add-SdUiFixText $n2.UList @(@{ T = 'Wynik cofania'; B = $true; C = '#0F6CBD'; S = 14 }) '0,0,0,4')
            $labels = @{ ok = @('OK', '#067647'); skip = @('POMINIĘTO', '#667085'); error = @('BŁĄD', '#B42318') }
            foreach ($r in $res) {
                $lb = $labels[[string]$r.Result]
                if (-not $lb) { $lb = @([string]$r.Result, '#475467') }
                [void](Add-SdUiFixText $n2.UList @(@{ T = '[' + $lb[0] + '] '; B = $true; C = $lb[1] }, @{ T = $r.Text; B = $true }, @{ T = $r.Message; C = '#475467'; NL = $true }) '0,4,0,4')
            }
            $okN = @($res | Where-Object { $_.Result -eq 'ok' }).Count
            $n2.UStatus.Text = ('Cofnięto {0} z {1}.' -f $okN, $res.Count) + ' Część zmian (usługi, plik wymiany, TRIM) zadziała po ponownym uruchomieniu komputera.' + $(if ($logPath) { "`nDziennik: " + $logPath } else { '' })
            $n2.URun.IsEnabled = $false
            if ($logPath) { $global:SdUi.C.FooterText.Text = 'Dziennik cofnięcia napraw: ' + $logPath }
        })
    $ui.TestWindow = $w
    [void]$w.ShowDialog()
    $ui.UndoDlg = $null
}

# ------------------------------------------------------------------ o programie

function Get-SdUiKnowledgeInfo {
    # Jak Get-SdKnowledgeInfo; autotest może podać datę bieżącą (SERWISDIAG_TEST_NOW=2027-06-01), żeby pokazać baner.
    $now = Get-Date
    $d = [datetime]::MinValue
    if ($global:SdUi.SelfTest -and [datetime]::TryParseExact([string]$env:SERWISDIAG_TEST_NOW, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $now = $d }
    return (Get-SdKnowledgeInfo -Now $now)
}

function Show-SdUiAbout {
    $ui = $global:SdUi
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiAboutXaml)))
    $w.Owner = $ui.Window
    Set-SdUiWindowFit $w
    $n = @{}
    foreach ($name in 'AVersion', 'APanel', 'ALicense', 'AUpdate', 'AClose') { $n[$name] = $w.FindName($name) }
    $n.AVersion.Text = ('wersja {0} · licencja {1}' -f $global:SdVersion, $global:SdLicense)
    # pary jako tablice asocjacyjne - tablice @('a', 'b') w @( ... ) PowerShell spłaszczyłby w jedną listę napisów
    $sections = @(
        @{ H = 'Do czego służy'; V = 'Diagnostyka i naprawa komputerów z Windows 8, 8.1, 10 i 11: sprzęt, dyski, bateria, awarie, sterowniki, zabezpieczenia, aktualizacje, sieć i autostart. Działa bez instalacji, także z pendrive''a. Wersja zainstalowana może monitorować system w tle i sama się aktualizuje.' }
        @{ H = 'Autor'; V = $global:SdAuthor }
        @{ H = 'Licencja'; V = 'MIT - program można bezpłatnie używać (także w firmie), kopiować, zmieniać i rozpowszechniać, pod warunkiem zachowania informacji o autorze i licencji.' }
        @{ H = 'Strona projektu'; V = $(if ($global:SdProjectUrl) { $global:SdProjectUrl } else { 'jeszcze nie opublikowano' }) }
        @{ H = 'Baza wiedzy (okresy wsparcia Windows i ESU)'; V = (Get-SdUiKnowledgeInfo).Text }
        @{ H = 'Pliki programu'; V = $(if ($global:SdIntegrity) { [string]$global:SdIntegrity.Summary } else { 'nie sprawdzono' }) }
        @{ H = 'Bez gwarancji'; V = 'Program jest udostępniany „tak jak jest”, bez jakiejkolwiek gwarancji. Naprawy zmieniają ustawienia systemu: program tworzy przed nimi punkt przywracania i zapisuje dziennik zmian (zmiany ustawień można cofnąć), ale za ich użycie odpowiada osoba, która je uruchamia. Przed poważnymi zmianami zrób kopię danych.' }
        @{ H = 'Prywatność'; V = 'Program pracuje lokalnie i nie wysyła danych o komputerze. Z internetem łączy się tylko w testach łączności, przy wyszukiwaniu sterowników w Windows Update i przy sprawdzaniu nowej wersji na GitHubie (na żądanie, a w wersji zainstalowanej także raz na dobę - można to wyłączyć w ustawieniach).' }
    )
    foreach ($s in $sections) { [void](Add-SdUiFixText $n.APanel @(@{ T = $s.H; B = $true; C = '#0F6CBD' }, @{ T = $s.V; C = '#344054'; NL = $true }) '0,0,0,12') }
    if (-not (Get-SdGitHubRepo $global:SdProjectUrl)) {
        $n.AUpdate.IsEnabled = $false
        $n.AUpdate.ToolTip = 'Program nie ma jeszcze adresu strony projektu na GitHubie.'
    }
    $n.ALicense.Add_Click({
            $lic = Join-Path $global:SdUi.Root 'LICENSE'
            $txt = 'Brak pliku LICENSE w folderze programu. Program jest udostępniany na licencji MIT.'
            if (Test-Path -LiteralPath $lic) { $txt = [System.IO.File]::ReadAllText($lic, [System.Text.Encoding]::UTF8) }
            [void][System.Windows.MessageBox]::Show($w, $txt, 'Licencja', 'OK', 'Information')
        }.GetNewClosure())
    $n.AUpdate.Add_Click({
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
            try { $rel = Get-SdLatestRelease } finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
            try { Save-SdUpdateCheckState $rel } catch { }
            $txt = Get-SdLatestReleaseText $rel
            if ($rel.Ok -and $rel.Newer) {
                Show-SdUiUpdateBanner $rel
                if (Get-SdInstallMode $global:SdUi.Root) {
                    if ([string][System.Windows.MessageBox]::Show($w, ('Dostępna jest nowa wersja: {0} (masz {1}).' -f $rel.Latest, $global:SdVersion) + "`n`nZaktualizować teraz?", 'Nowa wersja', 'YesNo', 'Question') -eq 'Yes') { $w.Close(); Invoke-SdUiUpdate -Confirmed }
                } elseif ([string][System.Windows.MessageBox]::Show($w, ($txt + "`n`nOtworzyć stronę wydania?"), 'Nowa wersja', 'YesNo', 'Question') -eq 'Yes') { try { Start-Process $rel.Url } catch { } }
            } else { [void][System.Windows.MessageBox]::Show($w, $txt, 'Nowa wersja', 'OK', 'Information') }
        }.GetNewClosure())
    $ui.TestWindow = $w
    [void]$w.ShowDialog()
}

# ------------------------------------------------------------------ aktualizacje programu

function Show-SdUiUpdateBanner {
    # Baner „Dostępna nowa wersja”: wersja zainstalowana aktualizuje się sama, przenośna pokazuje stronę wydania.
    param($Release)
    $ui = $global:SdUi; $c = $ui.C
    $ui.UpdateRel = $Release
    $inst = [bool](Get-SdInstallMode $ui.Root)
    $c.UpdBannerText.Text = ('Dostępna jest nowa wersja SerwisDiag {0} (masz {1}).' -f $Release.Latest, $global:SdVersion) + $(if ($inst) { '' } else { ' Wersję przenośną pobierz ze strony projektu.' })
    $c.BtnUpdate.Content = $(if ($inst) { 'Zaktualizuj' } else { 'Pobierz' })
    $c.BtnUpdate.IsEnabled = $true
    $c.BtnUpdNotes.Visibility = $(if ($Release.Notes) { 'Visible' } else { 'Collapsed' })
    $c.UpdBanner.Visibility = 'Visible'
}

function Start-SdUiBackgroundTask {
    # Krótkie zadanie w tle w osobnym runspace z załadowanym programem; OnDone dostaje wynik (albo obiekt z polem Error).
    # Script: treść bez bloku param - parametry (Params i Root) dostaje pod nazwami kluczy.
    param([string]$Script, [hashtable]$Params, [scriptblock]$OnDone)
    $ui = $global:SdUi
    $p = @{ Root = $ui.Root }
    foreach ($kv in $Params.GetEnumerator()) { $p[[string]$kv.Key] = $kv.Value }
    $head = 'param(' + ((@($p.GetEnumerator() | ForEach-Object { '$' + $_.Key })) -join ', ') + ")`n`$SdRoot = `$Root`n. (Join-Path `$Root 'lib\Load.ps1')`n"
    $ps = New-SdUiTaskPs -Runspace ([runspacefactory]::CreateRunspace()) -Script ($head + $Script) -Params $p
    $ps.Runspace.Open()
    $task = @{ Ps = $ps; Async = $ps.BeginInvoke(); OnDone = $OnDone; Timer = (New-Object System.Windows.Threading.DispatcherTimer) }
    $task.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $task.Timer.Add_Tick({
            if (-not $task.Async.IsCompleted) { return }
            $task.Timer.Stop()
            $out = $null
            try { $out = @($task.Ps.EndInvoke($task.Async)) | Select-Object -Last 1 } catch { $out = [pscustomobject]@{ Error = $_.Exception.Message } }
            if (-not $out -and $task.Ps.Streams.Error.Count) { $out = [pscustomobject]@{ Error = [string]$task.Ps.Streams.Error[0] } }
            try { $task.Ps.Runspace.Dispose(); $task.Ps.Dispose() } catch { }
            & $task.OnDone $out
        }.GetNewClosure())
    $task.Timer.Start()
}

function Start-SdUiUpdateCheck {
    # Samoczynne sprawdzenie nowej wersji (wersja zainstalowana, raz na dobę) - w tle, bez blokowania okna.
    Start-SdUiBackgroundTask -Script '$r = Get-SdLatestRelease; try { Save-SdUpdateCheckState $r } catch { }; $r' -Params @{} -OnDone {
        param($rel)
        if ($rel -and $rel.PSObject.Properties['Newer'] -and $rel.Ok -and $rel.Newer) { Show-SdUiUpdateBanner $rel }
    }
}

function Invoke-SdUiUpdate {
    # Aktualizacja z okna: pobranie i sprawdzenie instalatora w tle, potem instalator i zamknięcie programu
    # (instalator uruchomi nową wersję ponownie). Wersja przenośna: strona wydania.
    param([switch]$Confirmed)
    $ui = $global:SdUi
    $rel = $ui.UpdateRel
    if (-not $rel) { return }
    if (-not (Get-SdInstallMode $ui.Root)) { try { Start-Process $rel.Url } catch { }; return }
    if ($ui.Scanning) { [void](Show-SdMessage 'Poczekaj na zakończenie diagnostyki - aktualizacja zamknie program.' 'Aktualizacja' 'Information'); return }
    if (-not $Confirmed) {
        $q = ('Zainstalować SerwisDiag {0} (masz {1})?' -f $rel.Latest, $global:SdVersion) + "`n`nProgram pobierze instalator z GitHuba, sprawdzi jego sumę kontrolną, zamknie się na czas aktualizacji i uruchomi ponownie. Ustawienia i raporty zostaną."
        if ((Show-SdMessage $q 'Aktualizacja' 'Question' 'YesNo') -ne 'Yes') { return }
    }
    $c = $ui.C
    $c.UpdBanner.Visibility = 'Visible'
    $c.UpdBannerText.Text = ('Pobieranie i sprawdzanie wersji {0}...' -f $rel.Latest)
    $c.BtnUpdate.IsEnabled = $false
    Start-SdUiBackgroundTask -Script 'try { [pscustomobject]@{ Setup = (Get-SdUpdatePackage -Release $Rel); Error = '''' } } catch { [pscustomobject]@{ Setup = ''''; Error = $_.Exception.Message } }' -Params @{ Rel = $rel } -OnDone {
        param($out)
        $u = $global:SdUi
        if (-not $out -or $out.Error -or -not $out.Setup) {
            Show-SdUiUpdateBanner $u.UpdateRel
            [void](Show-SdMessage ('Aktualizacja nie powiodła się:' + "`n" + $(if ($out) { $out.Error } else { 'brak wyniku' })) 'Aktualizacja' 'Warning')
            return
        }
        try {
            [void](Start-SdUpdateInstall -SetupPath $out.Setup -Root $u.Root -Relaunch)
            $u.Window.Close()
        } catch {
            Show-SdUiUpdateBanner $u.UpdateRel
            [void](Show-SdMessage ('Nie uruchomiono instalatora: ' + $_.Exception.Message) 'Aktualizacja' 'Warning')
        }
    }
}

function Update-SdUiHeader {
    $ui = $global:SdUi; $c = $ui.C
    $shop = [string]$ui.Settings.ShopName
    $contact = Join-NonEmpty @($ui.Settings.ShopPhone, $ui.Settings.ShopEmail) ' · '
    $c.ShopText.Text = $(if ($contact) { "$shop · $contact" } else { $shop })
}

function Save-SdUiScreenshot {
    param([string]$Path)
    $ui = $global:SdUi; $w = $ui.Window
    $w.UpdateLayout()
    [void]$w.Dispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $width = [int]$w.ActualWidth; $height = [int]$w.ActualHeight
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($w)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
}

# ------------------------------------------------------------------ okno główne

function Start-SdGui {
    param([string]$Root, [hashtable]$Settings, [switch]$SelfTest, [string]$ScreenshotPath, [string]$Ticket = '', [string]$Customer = '', [string]$Note = '', [switch]$Offline)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    Add-Type -AssemblyName System.Data
    if (-not (Initialize-SdNative)) {
        [void][System.Windows.MessageBox]::Show('Nie udało się zainicjować modułu natywnego (kompilacja C#). Program nie może wystartować.', 'SerwisDiag', 'OK', 'Error')
        return
    }
    . (Join-Path $Root 'lib\GuiTests.ps1')

    $ui = @{
        Root = $Root; Settings = $Settings; Ctx = $null; Result = $null; ReportPaths = $null; Selected = 'summary'
        Scanning = $false; ShownCount = -1; SelfTest = [bool]$SelfTest; CurrentTables = @(); SuppressTable = $false; CancelRequested = $false
        ReportDir = (Resolve-SdReportDir -Root $Root -Settings $Settings)
    }
    $global:SdUi = $ui
    $global:SD = New-SdContext -Root $Root       # kontekst pusty - pozwala funkcjom pomocniczym działać przed pierwszym skanem

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$global:SdUiXaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $ui.Window = $window
    $iconPath = Join-Path $Root 'assets\app.ico'
    if (Test-Path -LiteralPath $iconPath) {
        try { $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconPath))) } catch { Write-SdLog ('Ikona: ' + $_.Exception.Message) 'WARN' }
    }
    # mały ekran (laptop 1366x768, powiększenie 125-150%): okno w granicach ekranu, niższe minimalne wysokości list
    $ui.Compact = ((Get-SdUiWorkArea).Height -lt 760)
    Set-SdUiWindowFit $window -AllowMaximize:(-not $SelfTest)
    $ui.C = @{}
    foreach ($name in 'HeaderBorder', 'CtlGrid', 'OsChipText', 'AdminChip', 'AdminChipText', 'BtnAbout', 'BtnSettings', 'ShopText', 'AdminBanner', 'BtnElevate', 'KbBanner', 'KbBannerText', 'BtnKbAbout', 'UpdBanner', 'UpdBannerText', 'BtnUpdate', 'BtnUpdNotes', 'TxtTicket', 'TxtCustomer', 'TxtNote', 'CmbLevel',
        'BtnStart', 'BtnCancel', 'ChkDisk', 'ChkCpu', 'ChkNet', 'ChkVol', 'ChkDism', 'ChkOffline', 'ProgArea', 'ProgText', 'Prog', 'NavList', 'PageSummary', 'WelcomeCard', 'ResultPanel',
        'VerdictBar', 'Counters', 'VerdictTitle', 'VerdictText', 'FactsList', 'NoIssuesText', 'IssuesList', 'PageCategory', 'RowFindings', 'RowTables', 'EmptyText', 'CatTitle',
        'FindingsGrid', 'TableArea', 'TablesCombo', 'TableGrid', 'PageTools', 'ToolsPanel', 'FooterText', 'BtnFix', 'BtnReportTech', 'BtnReportCust', 'BtnPdf', 'BtnCompare', 'BtnFolder', 'BtnMore') {
        $ui.C[$name] = $window.FindName($name)
        if ($null -eq $ui.C[$name]) { Write-SdLog ('GUI: brak elementu ' + $name) 'ERROR' }
    }
    $c = $ui.C
    if ((Get-SdUiWorkArea).Width -lt 1200) {
        # wąski ekran: pole „Zgłoszenie” nie znika, a przycisk „Przerwij” mieści się w oknie
        $c.CtlGrid.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength(100)
        $c.CtlGrid.ColumnDefinitions[3].Width = New-Object System.Windows.GridLength(150)
        $c.CmbLevel.Width = 214
        $c.BtnStart.Content = '▶  Rozpocznij'
    }
    if ($ui.Compact) { $c.HeaderBorder.Padding = New-Object System.Windows.Thickness(22, 8, 22, 8) }

    # nagłówek / uprawnienia
    $os = Get-SdWinInfo
    $c.OsChipText.Text = ('{0} ({1})' -f $os.Caption, $os.Arch)
    $isAdmin = Test-SdAdmin
    $c.AdminChipText.Text = $(if ($isAdmin) { 'Administrator' } else { 'Bez uprawnień administratora' })
    if (-not $isAdmin) { $c.AdminBanner.Visibility = 'Visible'; $c.AdminChip.Background = Get-SdBrush '#B54708' }
    $window.Title = ('SerwisDiag {0} - diagnostyka systemu Windows' -f $global:SdVersion)
    $kb = Get-SdUiKnowledgeInfo
    if ($kb.Stale) {
        $c.KbBannerText.Text = 'Baza wiedzy programu (okresy wsparcia Windows i ESU): ' + $kb.Text + '. Daty wsparcia w raportach mogą być nieaktualne.'
        $c.KbBanner.Visibility = 'Visible'
    }
    Update-SdUiHeader
    $c.TxtTicket.Text = $Ticket; $c.TxtCustomer.Text = $Customer; $c.TxtNote.Text = $Note
    $c.ChkOffline.IsChecked = [bool]$Offline
    # w trybie bez internetu test prędkości nie ma sensu
    $syncNet = { $cc = $global:SdUi.C; $off = [bool]$cc.ChkOffline.IsChecked; if ($off) { $cc.ChkNet.IsChecked = $false }; $cc.ChkNet.IsEnabled = -not $off }
    $c.ChkOffline.Add_Checked($syncNet)
    $c.ChkOffline.Add_Unchecked($syncNet)
    & $syncNet

    Initialize-SdUiNav
    Initialize-SdUiTools
    Show-SdUiPage 'summary'

    # zdarzenia
    $c.NavList.Add_SelectionChanged({
            $sel = $global:SdUi.C.NavList.SelectedItem
            if ($sel) { Show-SdUiPage $sel.Key }
        })
    $c.TablesCombo.Add_SelectionChanged({ if (-not $global:SdUi.SuppressTable) { Update-SdUiTable } })
    $c.TableGrid.Add_AutoGeneratingColumn({
            param($s, $e)
            # nazwy kolumn z kropkami, nawiasami itp. wymagają wiązania przez indeksator [nazwa]
            $b = New-Object System.Windows.Data.Binding
            $b.Path = New-Object System.Windows.PropertyPath(('[' + $e.PropertyName + ']'))
            $e.Column.Binding = $b
            $e.Column.Header = $e.PropertyName
            $e.Column.MaxWidth = 520
            $e.Column.ElementStyle = $global:SdUi.Window.FindResource('WrapText')
        })
    $c.BtnStart.Add_Click({ Start-SdUiScan })
    $c.BtnCancel.Add_Click({ Stop-SdUiScan })
    $c.BtnSettings.Add_Click({ Show-SdUiSettings })
    $c.BtnAbout.Add_Click({ Show-SdUiAbout })
    $c.BtnKbAbout.Add_Click({ Show-SdUiAbout })
    $c.BtnUpdate.Add_Click({ Invoke-SdUiUpdate })
    $c.BtnUpdNotes.Add_Click({
            $r = $global:SdUi.UpdateRel
            if ($r) { [void](Show-SdMessage (('Co nowego w wersji {0}:' -f $r.Latest) + "`n`n" + $r.Notes) 'Nowa wersja' 'Information') }
        })
    # nowa wersja: wersja zainstalowana sprawdza raz na dobę, w tle (autotest nie łączy się z internetem)
    if (-not $SelfTest -and (Test-SdUpdateCheckDue -Root $Root -Settings $Settings)) { $window.Add_ContentRendered({ Start-SdUiUpdateCheck }) }
    $c.BtnElevate.Add_Click({
            # nowa instancja z uprawnieniami administratora przejmuje wpisane dane zlecenia
            $u = $global:SdUi
            $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', (Format-SdCmdArg (Join-Path $u.Root 'SerwisDiag.ps1')))
            foreach ($p in @(@('Ticket', $u.C.TxtTicket.Text), @('Customer', $u.C.TxtCustomer.Text), @('Note', $u.C.TxtNote.Text))) {
                $v = ([string]$p[1]).Trim()
                if ($v) { $a += ('-' + $p[0]); $a += (Format-SdCmdArg $v) }
            }
            try {
                Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList ($a -join ' ') -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
                $u.Window.Close()
            } catch { [void](Show-SdMessage 'Nie uruchomiono nowej instancji z uprawnieniami administratora (anulowano UAC).' 'SerwisDiag' 'Information') }
        })
    $c.BtnReportTech.Add_Click({ if ($global:SdUi.ReportPaths) { Start-Process -FilePath $global:SdUi.ReportPaths['Technical'] } })
    $c.BtnReportCust.Add_Click({ if ($global:SdUi.ReportPaths) { Start-Process -FilePath $global:SdUi.ReportPaths['Customer'] } })
    $c.BtnPdf.Add_Click({ Invoke-SdUiPdf })
    Initialize-SdUiMoreMenu
    $c.BtnCompare.Add_Click({ Show-SdUiCompare })
    $c.BtnFix.Add_Click({ Show-SdUiFixes })
    $c.BtnFolder.Add_Click({
            $u = $global:SdUi
            $d = Resolve-SdReportDir -Root $u.Root -Settings $u.Settings
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $d)
        })

    # zegar: postęp skanowania i wyniki na żywo
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
            $u = $global:SdUi
            if (-not $u.Ctx -or -not $u.Scanning) { return }
            $cc = $u.C
            $p = $u.Ctx.Progress
            if ($p.Total -gt 0) {
                $cc.Prog.Maximum = $p.Total
                $cc.Prog.Value = [math]::Max($p.Index - 1, 0)
                if (-not $u.CancelRequested) { $cc.ProgText.Text = ('[{0}/{1}]  {2}' -f $p.Index, $p.Total, $p.Title) }
            }
            $n = $u.Ctx.Findings.Count
            if ($n -ne $u.ShownCount) { $u.ShownCount = $n; Refresh-SdUiPage }
            if ($u.Async.IsCompleted) { Complete-SdUiScan; return }
            if ($u.CancelRequested -and $u.CancelAt -and ((Get-Date) - $u.CancelAt).TotalSeconds -gt 8) {
                # test nie reaguje na przerwanie (np. długie zapytanie) - zatrzymujemy potok
                try { [void]$u.Ps.BeginStop($null, $null) } catch { }
                $u.CancelAt = $null
            }
        })
    $ui.Timer = $timer

    $window.Add_Closing({
            $u = $global:SdUi
            if ($u.Scanning) {
                $u.Ctx.Cancel = $true
                try { [void]$u.Ps.BeginStop($null, $null) } catch { }
            }
        })

    if ($SelfTest) {
        # tryb automatycznego testu: okno poza ekranem, pełny skan szybki, zrzuty ekranu, zamknięcie
        $window.WindowStartupLocation = 'Manual'
        $window.Left = -3000; $window.Top = 40
        $window.ShowInTaskbar = $false
        $prefix = $ScreenshotPath
        if (-not $prefix) { $prefix = Join-Path ([System.IO.Path]::GetTempPath()) 'sd-selftest' }
        $ui.Self = @{ Prefix = $prefix; Steps = @('summary', 'storage', 'events', 'security', 'tools'); Index = 0; Phase = 'select'; Timer = $null }
        $ui.OnScanComplete = {
            $t = New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromMilliseconds(800)
            $t.Add_Tick({
                    $uu = $global:SdUi
                    $s = $uu.Self
                    if ($s.Index -ge $s.Steps.Count) { $s.Timer.Stop(); $uu.Window.Close(); return }
                    $key = $s.Steps[$s.Index]
                    if ($s.Phase -eq 'select') {
                        $idx = 0; $i = 0
                        foreach ($it in $uu.Nav) { if ($it.Key -eq $key) { $idx = $i }; $i++ }
                        $uu.C.NavList.SelectedIndex = $idx
                        $s.Phase = 'shot'
                    } else {
                        try { Save-SdUiScreenshot ($s.Prefix + '-' + $key + '.png') } catch { Write-SdLog ('Zrzut: ' + $_.Exception.Message) 'ERROR' }
                        $s.Index = $s.Index + 1
                        $s.Phase = 'select'
                    }
                })
            $global:SdUi.Self.Timer = $t
            $t.Start()
        }
        $window.Add_Loaded({
                # wartości podane w parametrach (-Ticket, -Customer) mają pierwszeństwo - autotest sprawdza też ich przekazanie
                $u = $global:SdUi
                if (-not $u.C.TxtTicket.Text) { $u.C.TxtTicket.Text = 'SELFTEST' }
                if (-not $u.C.TxtCustomer.Text) { $u.C.TxtCustomer.Text = 'Test automatyczny' }
                Start-SdUiScan
            })
    }

    [void]$window.ShowDialog()
    if ($ui.Rs) { try { $ui.Rs.Dispose() } catch { } }
}
