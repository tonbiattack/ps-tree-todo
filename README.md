# ps-tree-todo

PowerShell で動作するローカル完結型の TODO 管理ツールです。

## 使い方

```powershell
powershell -ExecutionPolicy Bypass -File .\ps-tree-todo.ps1
```

PowerShell 7 の場合:

```powershell
pwsh .\ps-tree-todo.ps1
```

## 機能

- TreeView による階層的な TODO 管理
- Markdown 形式での保存と再読込
- 追加 / 子追加 / 編集 / 完了切替 / 削除
- キーボードショートカット操作対応
- UTF-8 での保存

## ショートカットキー

| 操作 | ショートカットキー | アクセスキー |
| --- | --- | --- |
| タスク追加 | `Ctrl + N` / `Insert` | `Alt + A` |
| 子タスク追加 | `Ctrl + Shift + N` | `Alt + C` |
| タスク編集 | `F2` / `Enter` | `Alt + E` |
| 完了/未完了切替 | `Space` | `Alt + T` |
| タスク削除 | `Delete` | `Alt + D` |
| 保存 | `Ctrl + S` | `Alt + S` |
| 再読み込み | `Ctrl + R` / `F5` | `Alt + R` |
| ツリー移動 | `↑` / `↓` / `←` / `→` | - |

## 保存形式

`todos.md` に以下のような Markdown チェックリストが保存されます。

```markdown
- [ ] 個人開発
  - [ ] シレン6アシスタント
    - [x] 値段識別
    - [ ] READMEを書く
```

このアプリは Windows Forms を利用するため、Windows 10 / 11 の PowerShell 5.1 以上で動作します。
