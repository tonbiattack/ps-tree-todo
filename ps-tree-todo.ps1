[CmdletBinding()]
param(
    [switch]$StartMinimized
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:ScriptPath = $PSCommandPath
$script:ScriptDirectory = $PSScriptRoot

function New-ApplicationIcon {
    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(34, 91, 146))

    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 4)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLines($pen, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(7, 17),
        [System.Drawing.Point]::new(13, 23),
        [System.Drawing.Point]::new(26, 9)
    ))

    $pen.Dispose()
    $graphics.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $script:ApplicationIconBitmap = $bitmap
    return $icon
}

function Get-StartupShortcutPath {
    return Join-Path ([Environment]::GetFolderPath('Startup')) 'ps-tree-todo.lnk'
}

function Open-StartupFolder {
    Start-Process -FilePath (Get-StartupShortcutPath)
}

function New-TodoItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [bool]$Completed = $false
    )

    return [pscustomobject]@{
        Title = $Title.Trim()
        Completed = $Completed
        Children = [System.Collections.ArrayList]::new()
    }
}

function ConvertFrom-TodoMarkdown {
    param(
        [string]$Markdown
    )

    $rootItems = [System.Collections.ArrayList]::new()
    $stack = [System.Collections.Generic.List[object]]::new()

    if ([string]::IsNullOrWhiteSpace($Markdown)) {
        $script:LastParsedTodoItems = @()
        return
    }

    foreach ($line in ($Markdown -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -notmatch '^\s*-\s+\[(?<state>[ xX])\]\s*(?<title>.*)$') {
            continue
        }

        $indentLevel = [int](($line.Length - $line.TrimStart().Length) / 2)
        $state = $Matches['state']
        $title = $Matches['title'].Trim()

        if ([string]::IsNullOrWhiteSpace($title)) {
            continue
        }

        $item = New-TodoItem -Title $title -Completed ($state -match '[xX]')

        while ($stack.Count -gt $indentLevel) {
            $stack.RemoveAt($stack.Count - 1)
        }

        if ($indentLevel -eq 0) {
            [void]$rootItems.Add($item)
        }
        else {
            $parent = $stack[$indentLevel - 1]
            if ($null -ne $parent) {
                [void]$parent.Children.Add($item)
            }
        }

        [void]$stack.Add($item)
    }

    $script:LastParsedTodoItems = @($rootItems.ToArray())
    return $null
}

function Write-TodoMarkdownItems {
    param(
        [object[]]$Items,
        [int]$Depth = 0
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $Items) {
        $prefix = ('  ' * $Depth)
        $check = if ($item.Completed) { '[x]' } else { '[ ]' }
        [void]$lines.Add("$prefix- $check $($item.Title)")

        if ($item.Children.Count -gt 0) {
            foreach ($childLine in (Write-TodoMarkdownItems -Items @($item.Children) -Depth ($Depth + 1))) {
                [void]$lines.Add($childLine)
            }
        }
    }

    return @($lines)
}

function ConvertTo-TodoMarkdown {
    param(
        [object[]]$Items
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Items) {
        $check = if ($item.Completed) { '[x]' } else { '[ ]' }
        [void]$lines.Add("- $check $($item.Title)")

        if ($item.Children.Count -gt 0) {
            foreach ($childLine in (Write-TodoMarkdownItems -Items @($item.Children) -Depth 1)) {
                [void]$lines.Add($childLine)
            }
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-ParentTodoItem {
    param(
        [object[]]$Items,
        [object]$Target
    )

    foreach ($item in $Items) {
        if ($item -eq $Target) {
            return $null
        }

        if ($null -ne $item.Children) {
            foreach ($child in @($item.Children)) {
                if ($child -eq $Target) {
                    return $item
                }

                $result = Get-ParentTodoItem -Items @($child.Children) -Target $Target
                if ($null -ne $result) {
                    return $result
                }
            }
        }
    }

    return $null
}

function Get-TodoNodeText {
    param(
        [pscustomobject]$TodoItem
    )

    if ($null -eq $TodoItem) {
        return ''
    }

    $symbol = if ($TodoItem.Completed) { '☑' } else { '☐' }
    return "$symbol $($TodoItem.Title)"
}

function Populate-TreeNodeCollectionFromTodoItems {
    param(
        [object[]]$TodoItems,
        [System.Windows.Forms.TreeNodeCollection]$Collection
    )

    foreach ($todoItem in $TodoItems) {
        $node = [System.Windows.Forms.TreeNode]::new()
        $node.Tag = $todoItem
        $node.Text = Get-TodoNodeText -TodoItem $todoItem
        if ($todoItem.Completed) {
            $node.ForeColor = [System.Drawing.Color]::Gray
        }

        [void]$Collection.Add($node)

        if ($todoItem.Children.Count -gt 0) {
            Populate-TreeNodeCollectionFromTodoItems -TodoItems @($todoItem.Children) -Collection $node.Nodes
        }
    }
}

function Update-TreeNodeDisplay {
    param(
        [System.Windows.Forms.TreeNode]$Node
    )

    if ($null -eq $Node) {
        return
    }

    $todoItem = $Node.Tag
    if ($null -ne $todoItem) {
        $Node.Text = Get-TodoNodeText -TodoItem $todoItem
        if ($todoItem.Completed) {
            $Node.ForeColor = [System.Drawing.Color]::Gray
        }
        else {
            $Node.ForeColor = [System.Drawing.Color]::Black
        }
    }

    foreach ($child in $Node.Nodes) {
        Update-TreeNodeDisplay -Node $child
    }
}

function Refresh-TreeView {
    param(
        [System.Windows.Forms.TreeView]$TreeView
    )

    $TreeView.BeginUpdate()
    $TreeView.Nodes.Clear()
    Populate-TreeNodeCollectionFromTodoItems -TodoItems @($script:TodoRootItems) -Collection $TreeView.Nodes
    $TreeView.EndUpdate()
    $TreeView.ExpandAll()
    Refresh-ButtonState -TreeView $TreeView
}

function Refresh-ButtonState {
    param(
        [System.Windows.Forms.TreeView]$TreeView
    )

    $hasSelection = $null -ne $TreeView.SelectedNode
    $script:BtnEdit.Enabled = $hasSelection
    $script:BtnToggle.Enabled = $hasSelection
    $script:BtnDelete.Enabled = $hasSelection
    $script:BtnChildAdd.Enabled = $hasSelection
}

function Add-TodoItemAtSelection {
    param(
        [switch]$AsChild
    )

    $selectedNode = $script:TreeView.SelectedNode
    $title = [Microsoft.VisualBasic.Interaction]::InputBox('新しいタスク名を入力してください。', 'タスク追加', '新しいタスク')
    if ([string]::IsNullOrWhiteSpace($title)) {
        return
    }

    $newItem = New-TodoItem -Title $title

    if ($null -eq $selectedNode) {
        [void]$script:TodoRootItems.Add($newItem)
    }
    elseif ($AsChild) {
        [void]$selectedNode.Tag.Children.Add($newItem)
    }
    else {
        $parent = Get-ParentTodoItem -Items $script:TodoRootItems -Target $selectedNode.Tag

        if ($null -eq $parent) {
            $index = $script:TodoRootItems.IndexOf($selectedNode.Tag)
            if ($index -lt 0) {
                [void]$script:TodoRootItems.Add($newItem)
            }
            else {
                [void]$script:TodoRootItems.Insert($index + 1, $newItem)
            }
        }
        else {
            $index = $parent.Children.IndexOf($selectedNode.Tag)
            if ($index -lt 0) {
                [void]$parent.Children.Add($newItem)
            }
            else {
                [void]$parent.Children.Insert($index + 1, $newItem)
            }
        }
    }

    Refresh-TreeView -TreeView $script:TreeView
    Save-TodoFile -Path $script:DataFilePath -Silent
}

function Edit-SelectedTodoTitle {
    $selectedNode = $script:TreeView.SelectedNode
    if ($null -eq $selectedNode) {
        return
    }

    $originalTitle = $selectedNode.Tag.Title
    $newTitle = [Microsoft.VisualBasic.Interaction]::InputBox('タスク名を変更してください。', 'タスク編集', $originalTitle)
    if ([string]::IsNullOrWhiteSpace($newTitle)) {
        return
    }

    $selectedNode.Tag.Title = $newTitle.Trim()
    Update-TreeNodeDisplay -Node $selectedNode
    Save-TodoFile -Path $script:DataFilePath -Silent
}

function Toggle-SelectedTodoState {
    $selectedNode = $script:TreeView.SelectedNode
    if ($null -eq $selectedNode) {
        return
    }

    $selectedNode.Tag.Completed = -not $selectedNode.Tag.Completed
    Update-TreeNodeDisplay -Node $selectedNode
    Save-TodoFile -Path $script:DataFilePath -Silent
}

function Remove-SelectedTodo {
    $selectedNode = $script:TreeView.SelectedNode
    if ($null -eq $selectedNode) {
        return
    }

    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
        '選択中のタスクを削除しますか？`n配下のタスクもまとめて削除されます。',
        'タスク削除',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $parent = Get-ParentTodoItem -Items $script:TodoRootItems -Target $selectedNode.Tag
    if ($null -eq $parent) {
        [void]$script:TodoRootItems.Remove($selectedNode.Tag)
    }
    else {
        [void]$parent.Children.Remove($selectedNode.Tag)
    }

    $script:TreeView.SelectedNode = $null
    Refresh-TreeView -TreeView $script:TreeView
    Save-TodoFile -Path $script:DataFilePath -Silent
}

function Load-TodoFile {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $script:TodoRootItems = [System.Collections.ArrayList]::new()
        return
    }

    $markdown = Get-Content -LiteralPath $Path -Raw
    $script:TodoRootItems = [System.Collections.ArrayList]::new()
    $null = ConvertFrom-TodoMarkdown -Markdown $markdown
    foreach ($item in $script:LastParsedTodoItems) {
        [void]$script:TodoRootItems.Add($item)
    }

    Refresh-TreeView -TreeView $script:TreeView
}

function Save-TodoFile {
    param(
        [string]$Path,

        [switch]$Silent
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $content = ConvertTo-TodoMarkdown -Items @($script:TodoRootItems)
    if (-not [string]::IsNullOrEmpty($content)) {
        $content += [Environment]::NewLine
    }

    [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show('TODOをMarkdownとして保存しました。', '保存完了', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

function New-TaskForm {
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'ps-tree-todo'
    $form.Size = [System.Drawing.Size]::new(700, 500)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(500, 350)
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.KeyPreview = $true
    $treeView = [System.Windows.Forms.TreeView]::new()
    $treeView.Dock = 'Fill'
    $treeView.FullRowSelect = $true
    $treeView.ShowRootLines = $true
    $treeView.ShowLines = $true
    $treeView.HideSelection = $false
    $treeView.Anchor = 'Top,Bottom,Left,Right'
    $treeView.add_AfterSelect({
        Refresh-ButtonState -TreeView $script:TreeView
    })

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Dock = 'Bottom'
    $buttonPanel.AutoSize = $true
    $buttonPanel.FlowDirection = 'LeftToRight'
    $buttonPanel.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 8)
    $buttonPanel.WrapContents = $false

    $btnAdd = [System.Windows.Forms.Button]::new()
    $btnAdd.Text = '追加 (&A)'
    $btnAdd.AutoSize = $true
    $btnAdd.Add_Click({ Add-TodoItemAtSelection })

    $btnChildAdd = [System.Windows.Forms.Button]::new()
    $btnChildAdd.Text = '子追加 (&C)'
    $btnChildAdd.AutoSize = $true
    $btnChildAdd.Add_Click({ Add-TodoItemAtSelection -AsChild })

    $btnEdit = [System.Windows.Forms.Button]::new()
    $btnEdit.Text = '編集 (&E)'
    $btnEdit.AutoSize = $true
    $btnEdit.Add_Click({ Edit-SelectedTodoTitle })

    $btnToggle = [System.Windows.Forms.Button]::new()
    $btnToggle.Text = '完了切替 (&T)'
    $btnToggle.AutoSize = $true
    $btnToggle.Add_Click({ Toggle-SelectedTodoState })

    $btnDelete = [System.Windows.Forms.Button]::new()
    $btnDelete.Text = '削除 (&D)'
    $btnDelete.AutoSize = $true
    $btnDelete.Add_Click({ Remove-SelectedTodo })

    $btnSave = [System.Windows.Forms.Button]::new()
    $btnSave.Text = '保存 (&S)'
    $btnSave.AutoSize = $true
    $btnSave.Add_Click({ Save-TodoFile -Path $script:DataFilePath })

    $btnReload = [System.Windows.Forms.Button]::new()
    $btnReload.Text = '再読み込み (&R)'
    $btnReload.AutoSize = $true
    $btnReload.Add_Click({ Load-TodoFile -Path $script:DataFilePath })

    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $toolTip.SetToolTip($btnAdd, '追加 (Ctrl+N / Insert)')
    $toolTip.SetToolTip($btnChildAdd, '子追加 (Ctrl+Shift+N)')
    $toolTip.SetToolTip($btnEdit, '編集 (F2 / Enter)')
    $toolTip.SetToolTip($btnToggle, '完了切替 (Space)')
    $toolTip.SetToolTip($btnDelete, '削除 (Delete)')
    $toolTip.SetToolTip($btnSave, '保存 (Ctrl+S)')
    $toolTip.SetToolTip($btnReload, '再読み込み (Ctrl+R / F5)')

    $form.add_KeyDown({
        param($sender, $e)

        if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::S) {
            $e.SuppressKeyPress = $true
            Save-TodoFile -Path $script:DataFilePath
            return
        }

        if (($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::R) -or ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5)) {
            $e.SuppressKeyPress = $true
            Load-TodoFile -Path $script:DataFilePath
            return
        }

        if (($e.Control -and -not $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::N) -or ($e.KeyCode -eq [System.Windows.Forms.Keys]::Insert)) {
            $e.SuppressKeyPress = $true
            Add-TodoItemAtSelection
            return
        }

        if ($e.Control -and $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::N) {
            $e.SuppressKeyPress = $true
            Add-TodoItemAtSelection -AsChild
            return
        }

        if ($null -ne $script:TreeView.SelectedNode) {
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Space -and -not $e.Control -and -not $e.Alt) {
                $e.SuppressKeyPress = $true
                Toggle-SelectedTodoState
                return
            }

            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F2 -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                $e.SuppressKeyPress = $true
                Edit-SelectedTodoTitle
                return
            }

            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and -not $e.Control) {
                $e.SuppressKeyPress = $true
                Remove-SelectedTodo
                return
            }
        }
    })

    foreach ($button in @($btnAdd, $btnChildAdd, $btnEdit, $btnToggle, $btnDelete, $btnSave, $btnReload)) {
        [void]$buttonPanel.Controls.Add($button)
    }

    $content = [System.Windows.Forms.TableLayoutPanel]::new()
    $content.Dock = 'Fill'
    $content.ColumnCount = 1
    $content.RowCount = 2
    [void]$content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$content.Controls.Add($treeView, 0, 0)
    [void]$content.Controls.Add($buttonPanel, 0, 1)

    [void]$form.Controls.Add($content)

    $script:TreeView = $treeView
    $script:BtnAdd = $btnAdd
    $script:BtnChildAdd = $btnChildAdd
    $script:BtnEdit = $btnEdit
    $script:BtnToggle = $btnToggle
    $script:BtnDelete = $btnDelete
    $script:BtnSave = $btnSave
    $script:BtnReload = $btnReload
    $script:TodoRootItems = [System.Collections.ArrayList]::new()
    $script:DataFilePath = Join-Path $PSScriptRoot 'todos.md'
    $script:ApplicationIcon = New-ApplicationIcon
    $form.Icon = $script:ApplicationIcon

    $openMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new('ps-tree-todoを開く')
    $openMenuItem.Add_Click({
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    })

    $startupMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new('スタートアップフォルダーを開く')
    $startupMenuItem.Add_Click({ Open-StartupFolder })

    $exitMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new('終了')
    $exitMenuItem.Add_Click({
        Save-TodoFile -Path $script:DataFilePath -Silent
        $script:AllowExit = $true
        $form.Close()
    })

    $contextMenu = [System.Windows.Forms.ContextMenuStrip]::new()
    [void]$contextMenu.Items.Add($openMenuItem)
    [void]$contextMenu.Items.Add($startupMenuItem)
    [void]$contextMenu.Items.Add('-')
    [void]$contextMenu.Items.Add($exitMenuItem)

    $notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
    $notifyIcon.Icon = $script:ApplicationIcon
    $notifyIcon.Text = 'ps-tree-todo'
    $notifyIcon.ContextMenuStrip = $contextMenu
    $notifyIcon.Visible = $true
    $notifyIcon.Add_DoubleClick({
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    })

    $form.add_Resize({
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.Hide()
        }
    })
    $form.add_FormClosing({
        param($sender, $e)

        if (-not $script:AllowExit) {
            $e.Cancel = $true
            $form.Hide()
            return
        }

        Save-TodoFile -Path $script:DataFilePath -Silent
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        $contextMenu.Dispose()
        $script:ApplicationIcon.Dispose()
        $script:ApplicationIconBitmap.Dispose()
    })

    $script:NotifyIcon = $notifyIcon
    $script:AllowExit = $false

    Load-TodoFile -Path $script:DataFilePath
    Refresh-ButtonState -TreeView $treeView
    if ($StartMinimized) {
        $form.add_Shown({ $form.Hide() })
    }
    return $form
}

if ($MyInvocation.InvocationName -ne '.') {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    $form = New-TaskForm
    [System.Windows.Forms.Application]::Run($form)
}
