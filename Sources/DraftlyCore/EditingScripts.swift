public enum EditingScripts {
    public static let makeTasks = #"var t = editor.getSelectedText(); if (!t) { editor.setSelectedRange(0, editor.getText().length); t = editor.getText(); } editor.setSelectedText(t.split('\n').map(x => x.trim() ? (x.match(/^\s*- \[[ xX]\]/) ? x : '- [ ] ' + x.replace(/^[-*] /, '')) : x).join('\n'));"#
    public static let toggleTasks = #"var t = editor.getSelectedText(); if (!t) { editor.setSelectedRange(0, editor.getText().length); t = editor.getText(); } editor.setSelectedText(t.replace(/- \[([ xX])\]/g, (m, c) => c === ' ' ? '- [x]' : '- [ ]'));"#
    public static let insertDate = "editor.setSelectedText(draft.processTemplate('[[date]]'));"
    public static let indent = #"var t = editor.getSelectedText(); editor.setSelectedText('  ' + t.replace(/\n/g, '\n  '));"#
    public static let outdent = #"editor.setSelectedText(editor.getSelectedText().replace(/^ {1,2}/gm, ''));"#
}
