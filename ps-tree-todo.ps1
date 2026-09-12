Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
}

function Toggle-SelectedTodoState {
    $selectedNode = $script:TreeView.SelectedNode
    if ($null -eq $selectedNode) {
        return
    }

    $selectedNode.Tag.Completed = -not $selectedNode.Tag.Completed
    Update-TreeNodeDisplay -Node $selectedNode
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
        [string]$Path
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
    [System.Windows.Forms.MessageBox]::Show('TODOをMarkdownとして保存しました。', '保存完了', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function New-TaskForm {
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'ps-tree-todo'
    $form.Size = [System.Drawing.Size]::new(700, 500)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(500, 350)
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false

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
    $btnAdd.Text = '追加'
    $btnAdd.AutoSize = $true
    $btnAdd.Add_Click({ Add-TodoItemAtSelection })

    $btnChildAdd = [System.Windows.Forms.Button]::new()
    $btnChildAdd.Text = '子追加'
    $btnChildAdd.AutoSize = $true
    $btnChildAdd.Add_Click({ Add-TodoItemAtSelection -AsChild })

    $btnEdit = [System.Windows.Forms.Button]::new()
    $btnEdit.Text = '編集'
    $btnEdit.AutoSize = $true
    $btnEdit.Add_Click({ Edit-SelectedTodoTitle })

    $btnToggle = [System.Windows.Forms.Button]::new()
    $btnToggle.Text = '完了切替'
    $btnToggle.AutoSize = $true
    $btnToggle.Add_Click({ Toggle-SelectedTodoState })

    $btnDelete = [System.Windows.Forms.Button]::new()
    $btnDelete.Text = '削除'
    $btnDelete.AutoSize = $true
    $btnDelete.Add_Click({ Remove-SelectedTodo })

    $btnSave = [System.Windows.Forms.Button]::new()
    $btnSave.Text = '保存'
    $btnSave.AutoSize = $true
    $btnSave.Add_Click({ Save-TodoFile -Path $script:DataFilePath })

    $btnReload = [System.Windows.Forms.Button]::new()
    $btnReload.Text = '再読み込み'
    $btnReload.AutoSize = $true
    $btnReload.Add_Click({ Load-TodoFile -Path $script:DataFilePath })

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

    Load-TodoFile -Path $script:DataFilePath
    Refresh-ButtonState -TreeView $treeView
    return $form
}

if ($MyInvocation.InvocationName -ne '.') {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    $form = New-TaskForm
    [System.Windows.Forms.Application]::Run($form)
}
