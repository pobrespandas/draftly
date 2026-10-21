public enum EditingScripts {
    public static let makeTasks = #"var t = editor.getSelectedText(); if (!t) { editor.setSelectedRange(0, editor.getText().length); t = editor.getText(); } editor.setSelectedText(t.split('\n').map(x => x.trim() ? (x.match(/^\s*- \[[ xX]\]/) ? x : '- [ ] ' + x.replace(/^[-*] /, '')) : x).join('\n'));"#
    public static let toggleTasks = #"var t = editor.getSelectedText(); if (!t) { editor.setSelectedRange(0, editor.getText().length); t = editor.getText(); } editor.setSelectedText(t.replace(/- \[([ xX])\]/g, (m, c) => c === ' ' ? '- [x]' : '- [ ]'));"#
    public static let insertDate = "editor.setSelectedText(draft.processTemplate('[[date]]'));"
    public static let indent = #"var tab = editor.preferredTabString; var t = editor.getSelectedText(); editor.setSelectedText(tab + t.replace(/\n/g, '\n' + tab));"#
    public static let outdent = #"var tab = editor.preferredTabString; editor.setSelectedText(editor.getSelectedText().split('\n').map(line => { if (line.startsWith(tab)) return line.slice(tab.length); if (tab !== '\t') { var n = 0; while (n < tab.length && line[n] === ' ') n++; return line.slice(n); } return line; }).join('\n'));"#
}
