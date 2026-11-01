import Foundation
import CryptoKit

public struct DefaultActionCatalogInstallation: Equatable, Sendable {
    public let groupNames: [String]
    public let actionCount: Int
}

public enum DefaultActionCatalog {
    public static let referenceVersion = "Drafts 54.1.2 (947)"
    public static let revision = 2
    public static let groupNames = ["Basic", "Editing", "Markdown", "Tools", "Processing"]

    public static var groups: [ActionGroupRecord] {
        groupNames.enumerated().map { order, name in
            var group = ActionGroupRecord(name: name)
            group.id = stableID("group/" + name)
            group.order = order
            return group
        }
    }

    public static var actions: [DraftAction] {
        basic + editing + markdown + tools + processing
    }

    public static func restoredBundle(existingGroupNames: [String]) -> (groups: [ActionGroupRecord], actions: [DraftAction]) {
        var occupied = Set(existingGroupNames)
        var names: [String: String] = [:]
        for base in groupNames {
            var number = 1
            var candidate = base + " (Default)"
            while occupied.contains(candidate) {
                number += 1
                candidate = base + " (Default \(number))"
            }
            occupied.insert(candidate)
            names[base] = candidate
        }
        let groups = groupNames.enumerated().map { order, base in
            var group = ActionGroupRecord(name: names[base]!)
            group.id = UUID()
            group.order = existingGroupNames.count + order
            return group
        }
        let actions = actions.map { source in
            var copy = source
            copy.id = UUID()
            copy.group = names[source.group]!
            copy.steps = source.steps.map { step in
                var copy = step
                copy.id = UUID()
                return copy
            }
            return copy
        }
        return (groups, actions)
    }

    private static var basic: [DraftAction] {
        [
            action("Copy", "Basic", "doc.on.doc", [.init("clipboard", ["template": "[[draft]]"])], legacyID: 1, shortcut: "1"),
            action("Share", "Basic", "square.and.arrow.up", [.init("share", ["template": "[[draft]]"])], legacyID: 2),
            action("Mail", "Basic", "envelope", [.init("mail", ["body": "[[draft]]", "subject": "[[title]]"]) ]),
            action("Message", "Basic", "message", [.init("message", ["body": "[[draft]]"]) ]),
            action("Google Search", "Basic", "magnifyingglass", [.init("url", ["url": "https://www.google.com/search?q=[[selection|draft]]"]) ]),
            action("Event", "Basic", "calendar", [.init("event", ["template": "[[draft]]"])], legacyID: 6),
            action("Send to Reminders", "Basic", "checklist", [.init("reminder", ["template": "[[draft]]"])], legacyID: 5),
            action("List in Reminders", "Basic", "list.bullet", [.init("listInReminders", ["template": "[[draft]]", "list": "Reminders"]) ]),
            action("Print - Plain Text", "Basic", "printer", [.init("print", ["template": "[[draft]]", "format": "plainText"]) ]),
            separator("Services", "Basic"),
            action("Save to Files", "Basic", "folder", [.init("file", ["template": "[[draft]]", "name": "[[safe_title]].txt"])], legacyID: 3),
            action("Save to Files as...", "Basic", "folder.badge.plus", [.init("export", ["template": "[[draft]]", "name": "[[safe_title]].txt"]) ]),
            bookmarkedFile("Save to iCloud Drive", bookmark: "iCloud Drive", symbol: "icloud.and.arrow.up", mode: "create", name: "[[safe_title]].md", template: "[[draft]]"),
            bookmarkedFile("Append to iCloud Journal", bookmark: "iCloud Drive", symbol: "icloud.and.arrow.up.fill", mode: "append", name: "Journal.md", template: "\n\n[[draft]]"),
            bookmarkedFile("Save to Google Drive", bookmark: "Google Drive", symbol: "externaldrive.badge.icloud", mode: "create", name: "[[safe_title]].md", template: "[[draft]]"),
            bookmarkedFile("Append to Google Drive Journal", bookmark: "Google Drive", symbol: "text.badge.plus", mode: "append", name: "Journal.md", template: "\n\n[[draft]]"),
            bookmarkedFile("Save to OneDrive", bookmark: "OneDrive", symbol: "externaldrive.badge.icloud", mode: "create", name: "[[safe_title]].md", template: "[[draft]]"),
            bookmarkedFile("Append to OneDrive Journal", bookmark: "OneDrive", symbol: "text.badge.plus", mode: "append", name: "Journal.md", template: "\n\n[[draft]]")
        ]
    }

    private static var editing: [DraftAction] {
        [
            separator("Undo/Redo", "Editing"),
            script("Undo", "Editing", "arrow.uturn.backward", "editor.undo();"),
            script("Redo", "Editing", "arrow.uturn.forward", "editor.redo();"),
            separator("Cursor Movement", "Editing"),
            script("Move Left", "Editing", "arrow.left", cursor(-1)),
            script("Move Right", "Editing", "arrow.right", cursor(1)),
            script("Move Back by Word", "Editing", "arrow.left.to.line", wordCursor(false)),
            script("Move Forward by Word", "Editing", "arrow.right.to.line", wordCursor(true)),
            separator("Commands", "Editing"),
            script("Find", "Editing", "magnifyingglass", "editor.showFind(false);"),
            script("Advanced Find", "Editing", "text.magnifyingglass", "editor.showFind(true);"),
            script("Make Tasks", "Editing", "checkmark.square", EditingScripts.makeTasks),
            script("Toggle Tasks", "Editing", "checkmark.square.fill", EditingScripts.toggleTasks),
            script("Insert Date", "Editing", "calendar.badge.plus", EditingScripts.insertDate),
            script("Insert Dictation", "Editing", "mic", "editor.showDictate();"),
            script("Dictate New Draft", "Editing", "mic.badge.plus", "var d=Draft.create(); d.update(); editor.load(d); editor.showDictate();"),
            action("Copy Selection", "Editing", "doc.on.doc", [.init("clipboard", ["template": "[[selection]]"]) ]),
            script("Paste as Plain Text", "Editing", "doc.on.clipboard", "editor.setSelectedText(app.getClipboard());"),
            action("Mail", "Editing", "envelope", [.init("mail", ["body": "[[selection|draft]]", "subject": "[[title]]"]) ]),
            action("Message", "Editing", "message", [.init("message", ["body": "[[selection|draft]]"]) ]),
            separator("Text Manipulation", "Editing"),
            script("Indent", "Editing", "increase.indent", EditingScripts.indent),
            script("Outdent", "Editing", "decrease.indent", EditingScripts.outdent),
            script("Move Line Up", "Editing", "arrow.up", moveLine(up: true)),
            script("Move Line Down", "Editing", "arrow.down", moveLine(up: false)),
            script("Duplicate Line", "Editing", "plus.square.on.square", duplicateLine),
            script("Previous Marker", "Editing", "chevron.up", marker(after: false)),
            script("Next Marker", "Editing", "chevron.down", marker(after: true)),
            separator("Utility", "Editing"),
            script("Toggle Theme", "Editing", "circle.lefthalf.filled", "app.themeMode = app.currentThemeMode === 'dark' ? 'light' : 'dark';")
        ]
    }

    private static var markdown: [DraftAction] {
        [
            wrap("Markdown Header (#)", "# ", "", "number", line: true),
            wrap("Markdown Bold (**)", "**", "**", "bold"),
            wrap("Markdown Emphasis (_)", "_", "_", "italic"),
            wrap("Markdown Link", "[", "](https://)", "link"),
            wrap("Inline Code (`)", "`", "`", "chevron.left.forwardslash.chevron.right"),
            wrap("Markdown Footnote (^)", "[^", "]", "textformat.superscript"),
            separator("Block Elements", "Markdown"),
            wrap("Markdown List", "- ", "", "list.bullet", line: true),
            wrap("Quote-Increase (>)", "> ", "", "increase.quotelevel", line: true),
            script("Quote-Decrease", "Markdown", "decrease.quotelevel", lineTransform("return line.replace(/^> ?/, '');")),
            wrap("Code Block (```)", "```\n", "\n```", "curlybraces"),
            action("Markdown Table", "Markdown", "tablecells", [.init("insertText", ["template": "| Header | Header |\n| --- | --- |\n| Cell | Cell |"]) ]),
            script("Edit Markdown Table", "Markdown", "tablecells.badge.ellipsis", editMarkdownTable),
            action("Preview", "Markdown", "eye", [.init("htmlpreview", ["template": "[[draft]]"])], legacyID: 4),
            script("Preview - RTL", "Markdown", "text.alignright", "var p=HTMLPreview.create(); p.show('<div dir=\"rtl\">'+MultiMarkdown.create().render(draft.content)+'</div>');"),
            separator("Utility", "Markdown"),
            action("Markdown Mail", "Markdown", "envelope", [.init("mail", ["body": "[[draft]]", "subject": "[[title]]", "renderMarkdown": "true"]) ]),
            action("Copy as HTML", "Markdown", "chevron.left.forwardslash.chevron.right", [.init("clipboard", ["template": "[[draft]]", "output": "html"]) ]),
            action("Copy as Rich Text", "Markdown", "doc.richtext", [.init("clipboard", ["template": "[[draft]]", "output": "richText"]) ]),
            script("Copy as Rich Text w/o Styles", "Markdown", "doc.plaintext", "app.htmlToClipboard('<div>'+HTML.escape(draft.content).replace(/\\n/g,'<br>')+'</div>');"),
            script("Paste as Markdown", "Markdown", "doc.on.clipboard", "editor.setSelectedText(app.getClipboard());"),
            action("Print - Markdown", "Markdown", "printer", [.init("print", ["template": "[[draft]]", "format": "markdown"]) ])
        ]
    }

    private static var tools: [DraftAction] {
        [
            separator("Change Selection", "Tools"),
            transform("UPPER", "textformat.size.larger", "return text.toUpperCase();"),
            transform("lower", "textformat.size.smaller", "return text.toLowerCase();"),
            transform("Title", "textformat", "return text.toLowerCase().replace(/(^|\\s)\\S/g, c => c.toUpperCase());"),
            transform("Sort", "arrow.up.arrow.down", "return text.split('\\n').sort((a,b) => a.localeCompare(b)).join('\\n');"),
            transform("Straighten Quotes", "quote.bubble", "return text.replace(/[“”]/g, '\"').replace(/[‘’]/g, \"'\");"),
            transform("Strip Diacritics", "character.book.closed", "return text.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');"),
            transform("Strip Line Feed", "text.append", "return text.replace(/\\s*\\n\\s*/g, ' ');"),
            transform("Hard Wrap", "text.word.spacing", "return text.replace(/(.{1,72})(?:\\s+|$)/g, '$1\\n').trimEnd();"),
            transform("Strip Extra Blank Lines", "text.badge.minus", "return text.replace(/\\n{3,}/g, '\\n\\n');"),
            transform("Trim Whitespace", "scissors", "return text.split('\\n').map(line => line.trim()).join('\\n').trim();"),
            transform("Remove Blank Lines", "line.3.horizontal.decrease", "return text.split('\\n').filter(line => line.trim()).join('\\n');"),
            script("Format Number", "Tools", "number", formatNumber),
            transform("Smart Parentheses", "parentheses", "return '(' + text + ')';"),
            transform("Smart Brackets", "ellipsis.rectangle", "return '[' + text + ']';"),
            transform("Smart Braces", "curlybraces", "return '{' + text + '}';"),
            separator("With Options", "Tools"),
            script("Change Case...", "Tools", "textformat", changeCaseOptions),
            script("Sort Lines...", "Tools", "arrow.up.arrow.down", sortLineOptions),
            script("Encode...", "Tools", "lock", encodeOptions),
            script("Decode...", "Tools", "lock.open", decodeOptions)
        ]
    }

    private static var processing: [DraftAction] {
        [
            script("Inbox", "Processing", "tray.and.arrow.down", "draft.isArchived = false; draft.update();"),
            script("Archive", "Processing", "archivebox", "draft.isArchived = true; draft.update();"),
            script("Save Version", "Processing", "clock.arrow.circlepath", "draft.update();"),
            script("Trash", "Processing", "trash", "draft.isTrashed = true; draft.update();"),
            script("Stats", "Processing", "chart.bar", "app.displayInfoMessage(draft.content.length + ' characters');"),
            separator("Tags & Flags", "Processing"),
            script("Update Tags...", "Processing", "tag", updateTags),
            script("Rename Tag...", "Processing", "tag.slash", renameTag),
            script("Flag", "Processing", "flag.fill", "draft.isFlagged = true; draft.update();"),
            script("Unflag", "Processing", "flag", "draft.isFlagged = false; draft.update();"),
            separator("Workspaces", "Processing"),
            script("Select Workspace", "Processing", "rectangle.3.group", selectWorkspace),
            script("Filter by Tag", "Processing", "tag", filterByTag),
            script("New Draft in Workspace", "Processing", "doc.badge.plus", newDraftInWorkspace),
            separator("Templates", "Processing"),
            action("New Draft with Template", "Processing", "doc.badge.plus", [.init("createDraft", ["template": "[[draft]]", "openInEditor": "true"]) ]),
            action("Apply Template", "Processing", "doc.text", [.init("insertText", ["template": "[[draft]]"]) ]),
            script("Previous Placeholder <|>", "Processing", "chevron.left", placeholder(after: false)),
            script("Next Placeholder <|>", "Processing", "chevron.right", placeholder(after: true))
        ]
    }

    static var legacyInboxSeparator: DraftAction { separator("Inbox", "Processing") }

    static func correctedInbox(_ source: DraftAction) -> DraftAction? {
        guard source == legacyInboxSeparator else { return nil }
        return processing.first { $0.name == "Inbox" }
    }

    private static func action(_ name: String, _ group: String, _ symbol: String, _ steps: [ActionStep], legacyID: Int? = nil, shortcut: String = "") -> DraftAction {
        var value = DraftAction(name: name, steps: steps)
        value.id = legacyID.map { UUID(uuidString: String(format: "DAAF7100-0000-4000-8000-%012d", $0))! } ?? stableID("action/\(group)/\(name)")
        value.group = group
        value.symbol = symbol
        value.shortcut = shortcut
        value.steps = steps.enumerated().map { index, source in
            var step = source
            step.id = stableID("step/\(group)/\(name)/\(index)")
            return step
        }
        value.presentation.order = actionsBefore(name, in: group)
        return value
    }

    private static func script(_ name: String, _ group: String, _ symbol: String, _ source: String) -> DraftAction {
        action(name, group, symbol, [.init("script", ["script": source])])
    }

    private static func separator(_ name: String, _ group: String) -> DraftAction {
        var value = action(name, group, "minus", [])
        value.scriptMetadata = ["isSeparator": "true"]
        return value
    }

    private static func bookmarkedFile(_ name: String, bookmark: String, symbol: String, mode: String,
                                       name fileName: String, template: String) -> DraftAction {
        action(name, "Basic", symbol, [.init("file", [
            "template": template,
            "name": fileName,
            "useBookmark": "true",
            "bookmarkName": bookmark,
            "writeType": mode
        ])])
    }

    private static func wrap(_ name: String, _ prefix: String, _ suffix: String, _ symbol: String, line: Bool = false) -> DraftAction {
        let source = line ? lineTransform("return \(quoted(prefix)) + line + \(quoted(suffix));") : "var text = editor.getSelectedText(); editor.setSelectedText(\(quoted(prefix)) + text + \(quoted(suffix)));"
        return script(name, "Markdown", symbol, source)
    }

    private static func transform(_ name: String, _ symbol: String, _ body: String) -> DraftAction {
        script(name, "Tools", symbol, "var range=editor.getSelectedRange(); if(!range[1]) range=[0,editor.getText().length]; var text=editor.getTextInRange(range[0],range[1]); var change=(function(text){\(body)})(text); editor.setTextInRange(range[0],range[1],change); editor.setSelectedRange(range[0],change.length);")
    }

    private static let changeCaseOptions = """
    var p=Prompt.create(); p.title='Change Case';
    p.addButton('UPPER','upper'); p.addButton('lower','lower'); p.addButton('Title','title');
    if(!p.show()){context.cancel();} else {
        var r=editor.getSelectedRange(); if(!r[1]) r=[0,editor.getText().length];
        var text=editor.getTextInRange(r[0],r[1]);
        if(p.buttonPressed==='upper') text=text.toUpperCase();
        else if(p.buttonPressed==='lower') text=text.toLowerCase();
        else text=text.toLowerCase().replace(/(^|\\s)\\S/g,function(c){return c.toUpperCase();});
        editor.setTextInRange(r[0],r[1],text); editor.setSelectedRange(r[0],text.length);
    }
    """

    private static let sortLineOptions = """
    var p=Prompt.create(); p.title='Sort Lines';
    p.addButton('Ascending','ascending'); p.addButton('Descending','descending');
    if(!p.show()){context.cancel();} else {
        var r=editor.getSelectedRange(); if(!r[1]) r=[0,editor.getText().length];
        var lines=editor.getTextInRange(r[0],r[1]).split('\\n').sort(function(a,b){return a.localeCompare(b);});
        if(p.buttonPressed==='descending') lines.reverse();
        var text=lines.join('\\n'); editor.setTextInRange(r[0],r[1],text); editor.setSelectedRange(r[0],text.length);
    }
    """

    private static let encodeOptions = optionTransform(title: "Encode", firstTitle: "URL Component",
        firstValue: "url", secondTitle: "HTML", secondValue: "html",
        first: "encodeURIComponent(text)", second: "HTML.escape(text)")

    private static let decodeOptions = optionTransform(title: "Decode", firstTitle: "URL Component",
        firstValue: "url", secondTitle: "HTML", secondValue: "html",
        first: "decodeURIComponent(text)", second: "HTML.unescape(text)")

    private static let updateTags = """
    var p=Prompt.create(); p.title='Update Tags';
    p.addTextField('tags','Tags',draft.tags.join(', ')); p.addButton('Update','update',true);
    if(!p.show()){context.cancel();} else {
        draft.tags=p.fieldValues.tags.split(',').map(function(tag){return tag.trim();}).filter(function(tag){return tag.length>0;});
        draft.update();
    }
    """

    private static let renameTag = """
    var p=Prompt.create(); p.title='Rename Tag';
    p.addTextField('oldTag','Current tag',''); p.addTextField('newTag','New tag',''); p.addButton('Rename','rename',true);
    if(!p.show()){context.cancel();} else {
        var oldTag=p.fieldValues.oldTag.trim(), newTag=p.fieldValues.newTag.trim();
        if(!oldTag||!newTag){context.fail('Enter both tag names.');}
        else { new Tag().renameTag(oldTag,newTag); }
    }
    """

    private static let editMarkdownTable = """
    var r=editor.getSelectedLineRange(), text=editor.getTextInRange(r[0],r[1]);
    var p=Prompt.create(); p.title='Edit Markdown Table'; p.addTextView('table','Markdown table',text); p.addButton('Apply','apply',true);
    if(!p.show()){context.cancel();} else {
        var replacement=String(p.fieldValues.table || '');
        editor.setTextInRange(r[0],r[1],replacement); editor.setSelectedRange(r[0],replacement.length);
    }
    """

    private static let formatNumber = """
    var r=editor.getSelectedRange(); if(!r[1]) r=[0,editor.getText().length];
    var raw=editor.getTextInRange(r[0],r[1]).trim();
    var p=Prompt.create(); p.title='Format Number'; p.addNumberField('decimals','Decimal places',2,false); p.addButton('Number','number',true); p.addButton('Percent','percent');
    if(!p.show()){context.cancel();} else {
        var value=Number(raw), digits=Math.max(0,Math.min(20,Math.round(Number(p.fieldValues.decimals))));
        if(!Number.isFinite(value)){context.fail('Select a valid number.');}
        else {
            if(p.buttonPressed==='percent') value*=100;
            var replacement=value.toLocaleString(undefined,{minimumFractionDigits:digits,maximumFractionDigits:digits})+(p.buttonPressed==='percent'?'%':'');
            editor.setTextInRange(r[0],r[1],replacement); editor.setSelectedRange(r[0],replacement.length);
        }
    }
    """

    private static let selectWorkspace = workspaceSelectionScript(body: "app.applyWorkspace(selected);")

    private static let filterByTag = """
    var p=Prompt.create(); p.title='Filter by Tag'; p.addTextField('tag','Tag',''); p.addButton('Filter','filter',true);
    if(!p.show()){context.cancel();} else {
        var tag=String(p.fieldValues.tag || '').trim();
        if(!tag){context.fail('Enter a tag.');} else { var workspace=Workspace.create(); workspace.tagFilter=tag; app.applyWorkspace(workspace); }
    }
    """

    private static let newDraftInWorkspace = workspaceSelectionScript(body: """
    app.applyWorkspace(selected);
    var created=Draft.create();
    created.tags=selected.tagFilter.split(',').map(function(tag){return tag.trim();}).filter(function(tag){return tag && tag.charAt(0)!=='!';});
    created.update(); editor.load(created);
    """)

    private static func workspaceSelectionScript(body: String) -> String {
        """
        var workspaces=Workspace.getAll(), picker=SelectPrompt.create(); picker.title='Select Workspace';
        workspaces.forEach(function(workspace,index){picker.addItem(String(index),workspace.name);});
        if(!workspaces.length){context.fail('Create a workspace first.');}
        else if(!picker.show()){context.cancel();}
        else { var selected=workspaces[Number(picker.selectedItem.id)]; \(body) }
        """
    }

    private static func optionTransform(title: String, firstTitle: String, firstValue: String,
                                        secondTitle: String, secondValue: String,
                                        first: String, second: String) -> String {
        """
        var p=Prompt.create(); p.title='\(title)';
        p.addButton('\(firstTitle)','\(firstValue)'); p.addButton('\(secondTitle)','\(secondValue)');
        if(!p.show()){context.cancel();} else {
            var r=editor.getSelectedRange(); if(!r[1]) r=[0,editor.getText().length];
            var text=editor.getTextInRange(r[0],r[1]);
            text=p.buttonPressed==='\(firstValue)' ? \(first) : \(second);
            editor.setTextInRange(r[0],r[1],text); editor.setSelectedRange(r[0],text.length);
        }
        """
    }

    private static func lineTransform(_ body: String) -> String {
        "var range=editor.getSelectedLineRange(); var text=editor.getTextInRange(range[0],range[1]); var change=text.split('\\n').map(function(line){\(body)}).join('\\n'); editor.setTextInRange(range[0],range[1],change); editor.setSelectedRange(range[0],change.length);"
    }

    private static func cursor(_ delta: Int) -> String {
        "var range=editor.getSelectedRange(); editor.setSelectedRange(Math.max(0,Math.min(editor.getText().length,range[0]+\(delta))),0);"
    }

    private static func wordCursor(_ forward: Bool) -> String {
        forward
            ? "var t=editor.getText(),p=editor.getSelectedRange()[0],m=t.slice(p).match(/\\s*\\S+/); editor.setSelectedRange(m?p+m[0].length:t.length,0);"
            : "var t=editor.getText(),p=editor.getSelectedRange()[0],m=t.slice(0,p).match(/\\S+\\s*$/); editor.setSelectedRange(m?p-m[0].length:0,0);"
    }

    private static func moveLine(up: Bool) -> String {
        up
            ? "var r=editor.getSelectedLineRange(),t=editor.getText(),before=t.slice(0,r[0]),i=before.lastIndexOf('\\n',Math.max(0,before.length-2)); if(r[0]>0){var start=i<0?0:i+1,prev=t.slice(start,r[0]),cur=t.slice(r[0],r[0]+r[1]); editor.setTextInRange(start,prev.length+cur.length,cur+prev); editor.setSelectedRange(start,cur.length);}"
            : "var r=editor.getSelectedLineRange(),t=editor.getText(),end=r[0]+r[1],next=t.indexOf('\\n',end); if(end<t.length){var stop=next<0?t.length:next+1,cur=t.slice(r[0],end),following=t.slice(end,stop); editor.setTextInRange(r[0],stop-r[0],following+cur); editor.setSelectedRange(r[0]+following.length,cur.length);}"
    }

    private static let duplicateLine = "var r=editor.getSelectedLineRange(),t=editor.getTextInRange(r[0],r[1]); editor.setTextInRange(r[0]+r[1],0,t); editor.setSelectedRange(r[0]+r[1],r[1]);"

    private static func marker(after: Bool) -> String {
        after
            ? "var m=editor.navigationMarkerAfter(editor.getSelectedRange()[0]); if(m) editor.setSelectedRange(m.location,0);"
            : "var m=editor.navigationMarkerBefore(editor.getSelectedRange()[0]); if(m) editor.setSelectedRange(m.location,0);"
    }

    private static func placeholder(after: Bool) -> String {
        after
            ? "var t=editor.getText(),p=editor.getSelectedRange()[0],n=t.indexOf('<|>',p); if(n>=0) editor.setSelectedRange(n,3);"
            : "var t=editor.getText(),p=editor.getSelectedRange()[0],n=t.lastIndexOf('<|>',Math.max(0,p-1)); if(n>=0) editor.setSelectedRange(n,3);"
    }

    private static func quoted(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }

    private static func actionsBefore(_ name: String, in group: String) -> Int {
        let inventories: [String: [String]] = [
            "Basic": ["Copy", "Share", "Mail", "Message", "Google Search", "Event", "Send to Reminders", "List in Reminders", "Print - Plain Text", "Services", "Save to Files", "Save to Files as...", "Save to iCloud Drive", "Append to iCloud Journal", "Save to Google Drive", "Append to Google Drive Journal", "Save to OneDrive", "Append to OneDrive Journal"],
            "Editing": ["Undo/Redo", "Undo", "Redo", "Cursor Movement", "Move Left", "Move Right", "Move Back by Word", "Move Forward by Word", "Commands", "Find", "Advanced Find", "Make Tasks", "Toggle Tasks", "Insert Date", "Insert Dictation", "Dictate New Draft", "Copy Selection", "Paste as Plain Text", "Mail", "Message", "Text Manipulation", "Indent", "Outdent", "Move Line Up", "Move Line Down", "Duplicate Line", "Previous Marker", "Next Marker", "Utility", "Toggle Theme"],
            "Markdown": ["Markdown Header (#)", "Markdown Bold (**)", "Markdown Emphasis (_)", "Markdown Link", "Inline Code (`)", "Markdown Footnote (^)", "Block Elements", "Markdown List", "Quote-Increase (>)", "Quote-Decrease", "Code Block (```)", "Markdown Table", "Edit Markdown Table", "Preview", "Preview - RTL", "Utility", "Markdown Mail", "Copy as HTML", "Copy as Rich Text", "Copy as Rich Text w/o Styles", "Paste as Markdown", "Print - Markdown"],
            "Tools": ["Change Selection", "UPPER", "lower", "Title", "Sort", "Straighten Quotes", "Strip Diacritics", "Strip Line Feed", "Hard Wrap", "Strip Extra Blank Lines", "Trim Whitespace", "Remove Blank Lines", "Format Number", "Smart Parentheses", "Smart Brackets", "Smart Braces", "With Options", "Change Case...", "Sort Lines...", "Encode...", "Decode..."],
            "Processing": ["Inbox", "Archive", "Save Version", "Trash", "Stats", "Tags & Flags", "Update Tags...", "Rename Tag...", "Flag", "Unflag", "Workspaces", "Select Workspace", "Filter by Tag", "New Draft in Workspace", "Templates", "New Draft with Template", "Apply Template", "Previous Placeholder <|>", "Next Placeholder <|>"]
        ]
        return inventories[group]?.firstIndex(of: name) ?? 0
    }

    private static func stableID(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("Draftly defaults v1/\(key)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
