// Keep one JavaScript context for all steps in an action.
var __cancelled = false, __failure = null, __completed = false, __tags = {}, __draftCache = {};
function __call(op, value) {
    var result = JSON.parse(__host(op, JSON.stringify(value === undefined ? {} : value)));
    if (result.error) throw new Error(result.error);
    return result.value;
}
function __date(value) { return value == null ? undefined : new Date(value); }
function __define(target, name, get, set) { Object.defineProperty(target, name, {get, set, configurable:true}); }
function __normalTag(value) { return String(value).trim().normalize('NFC').toLowerCase(); }
function __validateTextRange(text, location, length) {
    if (!Number.isSafeInteger(location) || !Number.isSafeInteger(length) || location < 0 || length < 0 || location > text.length || length > text.length - location) throw new RangeError('The text range is outside the draft.');
}
function __range(text, location, length) {
    __validateTextRange(text,location,length);
    return __call('lineRange',{text,location,length});
}
class Syntax {
    constructor(name = 'Markdown', type = 'builtIn') { this.name = name; this.type = type; }
    static find(type, name) { return Syntax.getAll().find(s => s.type === type && s.name === name); }
    static getAll() { return __call('syntaxes').map(s => Object.assign(new Syntax(), s)); }
    get installURL() { return __call('syntaxInstallURL',{name:this.name,type:this.type}); }
}
class Theme {
    constructor(name = 'Default', type = 'builtIn') { this.name = name; this.type = type; }
    static find(type, name) { return Theme.getAll().find(s => s.type === type && s.name === name); }
    static getAll() { return __call('themes').map(s => Object.assign(new Theme(), s)); }
    get installURL() { return 'draftly://theme?name=' + encodeURIComponent(this.name); }
}
class Task { constructor(value = {}) { Object.assign(this,value);Object.freeze(this); } }
function __syntaxAnalysis(text,syntax) { return __call('syntaxAnalysis',{text,syntax}); }
function __tasks(text,syntax='Markdown') { return __syntaxAnalysis(text,syntax).tasks.map(t=>new Task(t)); }
function __markers(text,syntax='Markdown') { return __syntaxAnalysis(text,syntax).markers; }
function __taskChange(text,syntax,task,operation) { return __call('syntaxTaskChange',{text,syntax,task,operation}); }
class Draft {
    constructor(value) {
        let v = value || __call('newDraft');
        if (v.uuid && __draftCache[v.uuid]) return __draftCache[v.uuid];
        let {selectionStart,selectionLength,...fields}=v;
        Object.assign(this, {content:'',tags:[],isArchived:false,isTrashed:false,flagType:0,createdLatitude:0,createdLongitude:0,modifiedLatitude:0,modifiedLongitude:0}, fields);
        Object.defineProperty(this,'uuid',{value:v.uuid,writable:false,enumerable:true,configurable:false});
        this._selectionStart=selectionStart||0;this._selectionLength=selectionLength||0;
        this._createdAt = __date(v.createdAt); this._modifiedAt = __date(v.modifiedAt); this._explicitModifiedAt=false;
        this._syntax = typeof v.syntax === 'string' ? new Syntax(v.syntax) : Object.assign(new Syntax(), v.syntax || {});
        this._templateTags = {};
        __draftCache[this.uuid] = this;
    }
    static create() { return new Draft(); }
    static find(uuid) { if (__draftCache[uuid]) return __draftCache[uuid]; let v = __call('findDraft',{uuid}); return v ? new Draft(v) : undefined; }
    static query(query = '', folder = 'all', tags = [], omitTags = [], sort = 'modified', descending = false, flaggedToTop = false) {
        // Accept the previous Draftly boolean argument for existing scripts.
        let omitFlagged = typeof omitTags === 'boolean' ? omitTags : false;
        return __call('queryDrafts',{query,folder,tags,omitTags:Array.isArray(omitTags)?omitTags:[],omitFlagged,sort,descending,flaggedToTop}).map(v => new Draft(v));
    }
    static queryByTitle(title) { return Draft.query('', 'all').filter(d => d.title.toLocaleLowerCase().includes(title.toLocaleLowerCase())); }
    static flagged(flag) { return Draft.query('', 'flagged').filter(d => flag === undefined || d.flagType === (typeof flag === 'number' ? flag : ['none','red','orange','yellow','green','blue','purple','gray'].indexOf(flag))); }
    static recentTags() { return Tag.recentTags(); }
    get createdAt(){return this._createdAt;}set createdAt(value){this._createdAt=__date(value);}
    get modifiedAt(){return this._modifiedAt;}set modifiedAt(value){this._modifiedAt=__date(value);this._explicitModifiedAt=true;}
    get title() { return this.content.split(/\r\n|[\n\r\u2028\u2029]/)[0]; }
    get displayTitle() { return this.title.replace(/^#+\s*/, '') || 'Untitled'; }
    get lines() { return this.content.split('\n'); }
    get syntax() { return this._syntax; }
    set syntax(value) { this._syntax = typeof value === 'string' ? Syntax.getAll().find(s=>s.name===value)||new Syntax(value) : value; }
    get languageGrammar() { return this.syntax.name; }
    set languageGrammar(value) { this.syntax = value; }
    get isFlagged() { return this.flagType > 0; }
    set isFlagged(value) { this.flagType = value ? this.flagType || 1 : 0; }
    get folder() { return this.isTrashed ? 'trash' : this.isArchived ? 'archive' : 'inbox'; }
    set folder(value) { if(!['inbox','archive','trash'].includes(value))throw new RangeError('The draft folder is invalid.');this.isTrashed = value === 'trash'; if(value!=='trash')this.isArchived = value === 'archive'; }
    get permalink() { return 'draftly://open?uuid=' + this.uuid; }
    get urls() { return __call('detectURLs',{text:this.content}); }
    get linkedItems() { return __syntaxAnalysis(this.content,this.syntax.name).links; }
    get selectionStart() { return this.uuid === __call('editorNoteID') ? editor.getSelectedRange()[0] : this._selectionStart || 0; }
    get selectionLength() { return this.uuid === __call('editorNoteID') ? editor.getSelectedRange()[1] : this._selectionLength || 0; }
    get versions() { return __call('versions',{uuid:this.uuid}).map(v => new Version(v)); }
    get actionLogs() { return __call('actionLogs',{uuid:this.uuid}).map(v => new ActionLog(v)); }
    get tasks() { return __tasks(this.content,this.syntax.name); }
    get completedTasks() { return this.tasks.filter(t => t.isCompleted); }
    get incompleteTasks() { return this.tasks.filter(t => !t.isCompleted); }
    get navigationMarkers() { return __markers(this.content,this.syntax.name); }
    navigationMarkerAfter(location) { return this.navigationMarkers.find(m => m.location > location); }
    navigationMarkerBefore(location) { return this.navigationMarkers.filter(m => m.location < location).pop(); }
    completeTask(task) { return this._task(task,'complete'); }
    resetTask(task) { return this._task(task,'reset'); }
    advanceTask(task) { return this._task(task,'advance'); }
    _task(task,operation) { let c=__taskChange(this.content,this.syntax.name,task,operation);if(c.changed===false)return false;this.content=this.content.slice(0,c.range[0])+c.text+this.content.slice(c.range[0]+c.range[1]);return true; }

    addTag(tag) { tag = __normalTag(tag); if (tag && !this.hasTag(tag)) this.tags.push(tag); }
    removeTag(tag) { tag = __normalTag(tag); this.tags = this.tags.filter(t => __normalTag(t) !== tag); }
    hasTag(tag) { return this.tags.some(t => __normalTag(t) === __normalTag(tag)); }
    append(text, separator = '\n') { this.content += separator + text; }
    prepend(text, separator = '\n') { this.content = text + separator + this.content; }
    insert(text, line) { let lines = this.lines; lines.splice(Math.max(0,Math.min(line,lines.length)),0,text); this.content = lines.join('\n'); }
    linesWithPrefix(prefix) { return this.lines.filter(l => l.startsWith(prefix)); }
    bodyPreview(maxLength) { return this.lines.slice(1).join(' ').trim().slice(0,maxLength); }
    update() { let v=__call('updateDraft',{...this.toJSON(),_preserveDates:this._explicitModifiedAt});this._modifiedAt=__date(v.modifiedAt);this.tags=v.tags;this._explicitModifiedAt=false; }
    saveVersion() { __call('saveVersion',{uuid:this.uuid,content:this.content}); }
    processTemplate(text) { return __call('template',{note:this,text,tags:Object.assign({},__tags,this._templateTags)}); }
    processMustacheTemplate(text,additionalValues={},partials={}) { return MustacheTemplate.renderTemplate(text,{...this.toJSON(),title:this.title,displayTitle:this.displayTitle,body:this.lines.slice(1).join('\n'),...__tags,...this._templateTags,...additionalValues},partials); }
    setTemplateTag(key,value) { this._templateTags[key] = String(value); __tags[key] = String(value); __call('setTemplateTag',{key,value:String(value)}); }
    getTemplateTag(key) { return this._templateTags[key] === undefined ? __tags[key] : this._templateTags[key]; }
    toJSON() {
        return {uuid:this.uuid,content:this.content,tags:this.tags,isArchived:this.isArchived,isTrashed:this.isTrashed,isFlagged:this.isFlagged,flagType:this.flagType,syntax:this.syntax,
            createdAt:this.createdAt,modifiedAt:this.modifiedAt,createdLatitude:this.createdLatitude||0,createdLongitude:this.createdLongitude||0,modifiedLatitude:this.modifiedLatitude||0,modifiedLongitude:this.modifiedLongitude||0};
    }
}
class Version {
    constructor(v) {
        Object.assign(this,v);
        for (const [key,value] of Object.entries({uuid:v.uuid,content:v.content,createdAt:__date(v.createdAt)})) {
            Object.defineProperty(this,key,{value,writable:false,enumerable:true,configurable:false});
        }
    }
    get draft() { return Draft.find(this.draftUUID); }
    delete() { __call('deleteVersion',{uuid:this.uuid}); }
}
class ActionLog {
    constructor(v) { Object.assign(this,v); this.executedAt = __date(v.executedAt); }
    get draft() { return this.draftUUID ? Draft.find(this.draftUUID) : undefined; }
    get action() { let value=__call('actionForLog',{uuid:this.uuid});return value?new Action(value):undefined; }
    delete() { __call('deleteLog',{uuid:this.uuid}); }
}
class Action {
    constructor(v = {}) { Object.assign(this,v); }
    static find(name) { let v = __call('findAction',{name}); return v ? new Action(v) : undefined; }
    static recent() { return __call('recentActions').map(v => new Action(v)); }
    get installURL() { return __call('actionInstallURL',{uuid:this.uuid}); }
}
class ActionGroup {
    constructor(v = {}) { Object.assign(this,v); }
    static find(name) { return ActionGroup.getAll().find(g => g.name === name); }
    static getAll() { return __call('actionGroups').map(v => new ActionGroup(v)); }
    get actions() { return __call('groupActions',{name:this.name}).map(v => new Action(v)); }
    get installURL() { return __call('groupInstallURL',{name:this.name}); }
}
class QueryDate {
    constructor(value = {}) { Object.assign(this,{type:'none',field:'modified',days:0,date:new Date()},value);this.date=__date(this.date); }
    static create() { return new QueryDate(); }
}
class Workspace {
    constructor(v = {}) {
        Object.assign(this,{name:'',queryString:'',tagFilter:'',tagFilterRequireAll:true,inboxIncludesFlagged:true,archiveIncludesFlagged:true,flaggedStatus:'any',showDate:true,showPreview:true,showTags:true,showSearchPreview:true,showLastAction:false,startDate:new QueryDate(),endDate:new QueryDate(),_sorts:{}},v);
        this.startDate=new QueryDate(this.startDate);this.endDate=new QueryDate(this.endDate);
        for(let key of ['loadActionBarGroup','loadActionListGroup'])if(this[key])this[key]=new ActionGroup(this[key]);
        for(let key of ['preferredDarkTheme','preferredLightTheme'])if(this[key])this[key]=Object.assign(new Theme(),this[key]);
    }
    static create() { return new Workspace(__call('defaultWorkspace')); }
    static find(name) { let v = __call('findWorkspace',{name}); return v ? new Workspace(v) : undefined; }
    static getAll() { return __call('workspaces').map(v => new Workspace(v)); }
    setAllSort(sort,descending,flagged) { this._sorts.all = {sort,descending,flagged}; }
    setInboxSort(sort,descending,flagged) { this._sorts.inbox = {sort,descending,flagged}; }
    setArchiveSort(sort,descending,flagged) { this._sorts.archive = {sort,descending,flagged}; }
    setFlaggedSort(sort,descending) { this._sorts.flagged = {sort,descending}; }
    query(folder = 'all') { return __call('queryWorkspace',{workspace:this,folder}).map(v => new Draft(v)); }
    update() { Object.assign(this,new Workspace(__call('updateWorkspace',this))); }
    get installURL() { return 'draftly://workspace?data='+encodeURIComponent(JSON.stringify(this)); }
}
class Tag {
    static query(queryString = '') { return __call('tags',{query:queryString}); }
    static recentTags() { return __call('recentTags'); }
    renameTag(oldTag,newTag) { return __call('renameTag',{oldTag,newTag}); }
}
class Prompt {
    constructor() { this.title=''; this.message=''; this.buttons=[]; this.fields=[]; this.fieldValues={}; this.isCancellable=true; }
    static create() { return new Prompt(); }
    addButton(title,value,isDefault,isDestructive,tintColor) { this.buttons.push({title,value:value===undefined?title:value,isDefault:!!isDefault,isDestructive:!!isDestructive,tintColor}); }
    _field(key,label,value,kind,options={}) { this.fields.push({...options,key,label,value,kind}); }
    addTextField(key,label,value='',options={}) { this._field(key,label,value,'text',options); }
    addTextView(key,label,value='',options={}) { this._field(key,label,value,'textView',options); }
    addNumberField(key,label,value,allowDecimals,options={}) { this._field(key,label,value,'number',{...options,allowDecimals}); }
    addPasswordField(key,label,value='') { this._field(key,label,value,'password'); }
    addSwitch(key,label,value) { this._field(key,label,!!value,'switch'); }
    addSelect(key,label,options,selected=[],multiple=false) { this._field(key,label,selected,'select',{options,multiple}); }
    addSegmentedControl(key,label,options,selected) { this._field(key,label,selected,'segment',{options}); }
    addPicker(key,label,columns,selectedRows) { this._field(key,label,selectedRows,'picker',{columns}); }
    addDatePicker(key,label,value,options={}) { this._field(key,label,value,'date',options); }
    addLabel(key,label,options={}) { this._field(key,label,null,'label',options); }
    addDivider() { this._field('', '',null,'divider'); }
    show() {
        const r=__call('prompt',this); if(r==null||r===false)return false;
        if(typeof r!=='object'||Array.isArray(r)||!Number.isInteger(r.index)||r.index<0||r.index>=Math.max(1,this.buttons.length)||r.fields==null||typeof r.fields!=='object'||Array.isArray(r.fields))throw new Error('The prompt returned an invalid response.');
        const fields={...r.fields};
        for(let f of this.fields)if(f.kind==='date')fields[f.key]=__date(fields[f.key]);
        this.fieldValues=fields;
        this.buttonPressed=this.buttons[r.index] ? this.buttons[r.index].value : 'Continue'; return true;
    }
}
class SelectPromptItem {
    constructor(id,title,subtitle,symbolName) { this.id=id; this.title=title; this.subtitle=subtitle; this.symbolName=symbolName; }
    static create(id,title,subtitle,symbolName) { return new SelectPromptItem(id,title,subtitle,symbolName); }
}
class SelectPrompt {
    constructor() { this.title=''; this.message=''; this.items=[]; }
    static create() { return new SelectPrompt(); }
    addItem(id,title,subtitle,symbolName) {
        if(id && typeof id==='object'){const item=id;id=item.id;title=item.title;subtitle=item.subtitle;symbolName=item.symbolName;}
        if(typeof id!=='string'||typeof title!=='string'||this.items.some(item=>item.id===id)){__call('message',{message:'SelectPrompt.addItem requires a unique string ID and a string title.'});return false;}
        this.items.push(new SelectPromptItem(id,title,subtitle,symbolName));return true;
    }
    show() { this.selectedItem=null;let r=__call('selectPrompt',this);if(!r||!Number.isInteger(r.index)||!this.items[r.index])return false;this.selectedItem=this.items[r.index];return true; }
}
var editor = {
    getText:()=>__call('editorText'),setText:text=>{__call('setEditorText',{text:String(text)});__syncEditorDraft();},
    getSelectedText:()=>__call('selection'),getSelectedRange:()=>__call('selectionRange'),
    setSelectedText:text=>{__call('replaceSelection',{text:String(text)});__syncEditorDraft();},setSelectedRange:(location,length)=>{__validateTextRange(editor.getText(),location,length);__call('setSelection',{location,length});},
    getTextInRange:(location,length)=>{__validateTextRange(editor.getText(),location,length);return __call('textInRange',{location,length});},setTextInRange:(location,length,text)=>{__validateTextRange(editor.getText(),location,length);__call('replaceRange',{location,length,text});__syncEditorDraft();},
    getLineRange:(location,length=0)=>__range(editor.getText(),location,length),
    getSelectedLineRange:()=>__range(editor.getText(),...editor.getSelectedRange()),
    load:d=>{__rememberSelection();__call('loadDraft',d);__syncEditorDraft();},activate:()=>{__call('activate');},deactivate:()=>{__call('ui',{operation:'deactivate'});},
    save:()=>{__call('saveEditor');},new:()=>{__rememberSelection();__call('newEditor');},
    navigationMarkers:()=>__markers(editor.getText(),editor.draft.syntax.name),navigationMarkerAfter:location=>__markers(editor.getText(),editor.draft.syntax.name).find(m=>m.location>location),
    navigationMarkerBefore:location=>__markers(editor.getText(),editor.draft.syntax.name).filter(m=>m.location<location).pop(),
    completeTask:task=>__editTask(task,'complete'),resetTask:task=>__editTask(task,'reset'),advanceTask:task=>__editTask(task,'advance')
};
function __editTask(task,operation){let c=__taskChange(editor.getText(),editor.draft.syntax.name,task,operation);if(c.changed===false)return false;editor.setTextInRange(...c.range,c.text);return true;}
function __rememberSelection(){let id=__call('editorNoteID'),range=__call('selectionRange');if(__draftCache[id]){__draftCache[id]._selectionStart=range[0];__draftCache[id]._selectionLength=range[1];}}
function __syncEditorDraft(){let id=__call('editorNoteID');if(__draftCache[id])__draftCache[id].content=editor.getText();}
__define(editor,'draft',()=>Draft.find(__call('editorNoteID')),d=>editor.load(d));
__define(editor,'tasks',()=>__tasks(editor.getText(),editor.draft.syntax.name));
__define(editor,'completedTasks',()=>editor.tasks.filter(t=>t.isCompleted));
__define(editor,'incompleteTasks',()=>editor.tasks.filter(t=>!t.isCompleted));
__define(editor,'urls',()=>__call('detectURLs',{text:editor.getText()}));
__define(editor,'linkedItems',()=>editor.draft.linkedItems);
__define(editor,'preferredTabString',()=>__call('ui',{operation:'get',key:'preferredTabString'}));
for(let name of ['undo','redo','showFind','arrange','showArrange','dictate','showDictate','scanDocument','transcribe','nextDraft','previousDraft']) editor[name]=(...args)=>{let result=__call('ui',{operation:name,args});if(name==='undo'||name==='redo')__syncEditorDraft();if(name==='nextDraft'||name==='previousDraft')return;return result;};
for(let name of ['isActive','linkModeEnabled','pinningEnabled','focusModeEnabled','typewriterScrollingEnabled']) __define(editor,name,()=>__call('ui',{operation:'get',key:name}),value=>__call('ui',{operation:'set',key:name,value}));
__define(editor,'recentDrafts',()=>__call('recentDrafts').map(v=>new Draft(v)));
__define(editor,'navigationMarkers',()=>__markers(editor.getText(),editor.draft.syntax.name));
var context = {configuredValues:{},callbackResponses:[],appleScriptResponses:[],previewValues:{},successParameters:{},
    cancel:message=>{if(message)__call('message',{message:String(message)});__cancelled=true;},fail:message=>{__failure=message||'Action failed';},addSuccessParameter:(name,value)=>{__call('successParameter',{name,value});context.successParameters[name]=value;}};
__define(context,'isCancelled',()=>__cancelled);
var app = {
    isPro:true,version:'0.1.0',areLiveActivitiesSupported:false,
    startLiveActivity:()=>{throw new Error('Live Activities are unavailable on macOS.');},
    stopLiveActivity:()=>{throw new Error('Live Activities are unavailable on macOS.');},
    displayInfoMessage:message=>__call('message',{message}),displaySuccessMessage:message=>__call('message',{message}),
    displayWarningMessage:message=>__call('message',{message}),displayErrorMessage:message=>__call('message',{message}),
    setClipboard:text=>__call('clipboard',{text}),getClipboard:()=>__call('getClipboard'),htmlToClipboard:html=>__call('htmlToClipboard',{html}),
    openURL:(url,useSafari)=>__call('openURL',{url,useSafari}),queueAction:(action,draft)=>__call('queueAction',{action,draft}),
    applyWorkspace:workspace=>__call('applyWorkspace',workspace===undefined?Workspace.create():workspace),setIdleDisabled:value=>__call('ui',{operation:'set',key:'isIdleDisabled',value}),
    selectDraft:()=>{let p=new SelectPrompt();Draft.query().forEach(d=>p.addItem(d.uuid,d.displayTitle));return p.show()?Draft.find(p.selectedItem.id):undefined;},
    openInNewWindow:d=>__call('ui',{operation:'openInNewWindow',draft:d}),lookup:text=>__call('lookup',{text})
};
for(let name of ['showActionList','hideActionList','showDraftList','hideDraftList','showDraftInfo','showQuickSearch','loadActionBarGroup','loadActionGroup','loadKeyboardActionGroup']) app[name]=value=>__call('ui',{operation:name,value});
for(let key of ['isActionListVisible','isDraftListVisible','isIdleDisabled','currentThemeMode','themeMode','darkTheme','lightTheme']) __define(app,key,()=>__call('ui',{operation:'get',key}),value=>__call('ui',{operation:'set',key,value}));
__define(app,'currentWorkspace',()=>new Workspace(__call('currentWorkspace')));
class Window {
    get currentWorkspace(){return app.currentWorkspace;}
    applyWorkspace(w){return app.applyWorkspace(w);}
    get selectedDrafts(){return __call('selectedDrafts').map(v=>new Draft(v));}
}
var window = new Window();
__define(app,'currentWindow',()=>window);
for(let key of ['areFiltersVisible','canCreateTab','floatOnTop','isActionListVisible','isDraftListVisible','isChatConsoleVisible']) __define(Window.prototype,key,()=>__call('ui',{operation:'get',key}),value=>__call('ui',{operation:'set',key,value}));
for(let name of ['showActionList','hideActionList','showDraftList','hideDraftList','showFilters','hideFilters','showDraftInfo','showQuickSearch','showCommandPalette','loadActionBarGroup','loadActionGroup','openInNewTab','showChatConsole','hideChatConsole']) Window.prototype[name]=function(value){return __call('ui',{operation:name,value});};
var Base64={encode:text=>__call('base64Encode',{text}),decode:text=>__call('base64Decode',{text})};
class Credential {
    constructor(name,description=''){this.name=name;this.description=description;this.fields=[];this.values={};}
    static create(name,description){return new Credential(name,description);}
    static createWithUsernamePassword(name,description){let c=new Credential(name,description);c.addTextField('username','Username');c.addPasswordField('password','Password');return c;}
    static createWithHostUsernamePassword(name,description){let c=Credential.createWithUsernamePassword(name,description);c.addURLField('host','Host');return c;}
    addPasswordField(key,label){this.fields.push({key,label,kind:'password'});}
    addTextField(key,label){this.fields.push({key,label,kind:'text'});}
    addURLField(key,label){this.addTextField(key,label);}
    authorize(){let saved=__call('getCredential',{name:this.name});if(saved){this.values=saved;return true;}let p=new Prompt();p.title=this.name;p.message=this.description;p.fields=this.fields.map(f=>({...f,value:this.values[f.key]||''}));p.addButton('Save');if(!p.show())return false;this.values=p.fieldValues;__call('setCredential',{name:this.name,values:this.values});return true;}
    getValue(key){return this.values[key];}setValue(key,value){this.values[key]=String(value);}
    forget(){this.values={};return __call('forgetCredential',{name:this.name});}
}
class Bookmark {
    constructor(name){this.name=name;}
    static findOrCreate(name){return __call('bookmark',{name})?new Bookmark(name):undefined;}
    forget(){return __call('forgetBookmark',{name:this.name});}
}
class FileManager {
    constructor(storage='local',bookmark){this.storage=storage;this.bookmark=bookmark;this.lastError=undefined;}
    static create(){return FileManager.createLocal();}static createLocal(){return new FileManager();}static createCloud(){return new FileManager('cloud');}
    static createForBookmark(bookmark){return new FileManager('bookmark',typeof bookmark==='string'?bookmark:bookmark.name);}
    _op(operation,values={}){try{let v=__call('fileAPI',{operation,storage:this.storage,bookmark:this.bookmark,...values});this.lastError=undefined;return v;}catch(e){this.lastError=e.message;return undefined;}}
    get basePath(){return this._op('basePath');}get baseURL(){return this._op('baseURL');}
    readString(path){return this._op('readString',{path});}writeString(path,text){return this._op('writeString',{path,text})===true;}
    readJSON(path){let text=this.readString(path);if(text===undefined)return undefined;try{return JSON.parse(text);}catch(e){this.lastError=e.message;return undefined;}}
    writeJSON(path,value){return this.writeString(path,JSON.stringify(value));}
    exists(path){return this._op('exists',{path})===true;}isDirectory(path){return this._op('isDirectory',{path})===true;}
    listContents(path){return this._op('listContents',{path});}createDirectory(path){return this._op('createDirectory',{path})===true;}
    copyItem(source,destination){return this._op('copyItem',{path:source,destination})===true;}moveItem(source,destination){return this._op('moveItem',{path:source,destination})===true;}
    getCreationDate(path){return __date(this._op('getCreationDate',{path}));}getModificationDate(path){return __date(this._op('getModificationDate',{path}));}
    setCreationDate(path,date){return this._op('setCreationDate',{path,date})===true;}setModificationDate(path,date){return this._op('setModificationDate',{path,date})===true;}
    getTags(path){return this._op('getTags',{path});}setTags(path,tags){return this._op('setTags',{path,tags})===true;}
}
class HTTPResponse { constructor(v={}){Object.assign(this,{success:false,statusCode:0,responseText:'',headers:{}},v);} }
class HTTP {constructor(){this.followRedirects=true;this.timeout=60;}static create(){return new HTTP();}request(settings){return new HTTPResponse(__call('http',{...settings,followRedirects:this.followRedirects,timeout:this.timeout}));}}
class XMLRPCResponse { constructor(v={}) { Object.assign(this, {success:false,statusCode:0,params:[]},v); } }
class XMLRPC { static request(url,methodName,params) { return new XMLRPCResponse(__call('xmlrpc',{url,methodName,params})); } }
class URL {
    constructor(url,base){if(url!==undefined)Object.assign(this,__call('parseURL',{url,base}));}
    static parse(url,base){try{return new URL(url,base);}catch(e){return undefined;}}
    get fragment(){return this.hash||'';}set fragment(v){this.hash=v.startsWith('#')?v:'#'+v;}
    toString(){return this.href;}
}
class CallbackURL {
    constructor(){this.baseURL='';this.parameters={};this.waitForResponse=true;this.callbackResponse={};this.status='created';}
    static create(){return new CallbackURL();}addParameter(key,value){this.parameters[key]=value;}
    get url(){return __call('buildURL',{url:this.baseURL,parameters:this.parameters});}
    open(){let r=__call('callbackURL',{url:this.url,waitForResponse:this.waitForResponse});this.status=r.status;this.callbackResponse=r.parameters||{};if(this.status==='success'){context.callbackResponses.push(this.callbackResponse);for(let k in this.callbackResponse){__tags['callback_'+k]=this.callbackResponse[k];__call('setTemplateTag',{key:'callback_'+k,value:String(this.callbackResponse[k])});}}return this.status==='success';}
}
class Share {static shareAsText(text){return __call('share',{text});}static shareAsFile(text,name){return __call('shareFile',{text,name});}static shareAsURL(url){return __call('shareURL',{url});}}
class Shortcut {
    constructor(){this.name='';this.text='';this.waitForResponse=true;this.response={};this.status='created';}
    static create(name,text=''){let s=new Shortcut();s.name=name;s.text=text;return s;}
    get result(){return this.response.result;}
    run(text){if(text!==undefined)this.text=text;try{let result=__call('shortcut',{name:this.name,text:this.text,waitForResponse:this.waitForResponse});this.response={result};this.status='success';if(this.waitForResponse)context.callbackResponses.push(this.response);__tags.shortcut_result=String(result);__call('setTemplateTag',{key:'shortcut_result',value:String(result)});return true;}catch(e){this.status='error';this.response={error:e.message};return false;}}
}
class AppleScript {
    constructor(source){this.source=source;}static create(source){return new AppleScript(source);}
    execute(subroutine,args=[]){try{this.lastResult=__call('appleScript',{source:this.source,subroutine,arguments:args});context.appleScriptResponses.push(this.lastResult);this.lastError=undefined;return true;}catch(e){this.lastError=e.message;return false;}}
}
class ShellScript {
    constructor(source){this.source=source;}static create(source){return new ShellScript(source);}
    execute(args=[]){let r=__call('shellScript',{source:this.source,arguments:args});this.standardOutput=r.stdout;this.standardError=r.stderr;return r.status===0;}
}
class HTML {static escape(text){return String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}static unescape(text){return __call('htmlUnescape',{text});}}
class HTMLPreview {
    constructor(){this.hideInterface=false;}static create(){return new HTMLPreview();}
    show(html){let r=__call('htmlPreview',{html,hideInterface:this.hideInterface});if(r&&r.values)context.previewValues=r.values;return r&&r.success!==undefined?r.success:!!r;}
}
class MultiMarkdown {
    constructor(){this.format='html';this.completeDocument=false;this.criticMarkup=false;this.criticMarkupAccept=false;this.criticMarkupReject=false;this.footnotesEnabled=true;this.markdownCompatibilityMode=false;this.noLabels=true;this.noMetadata=false;this.obfuscate=false;this.processHTML=true;this.randomFootnotes=false;this.smartQuotesEnabled=true;this.snippetOnly=false;this.transclude=false;}static create(){return new MultiMarkdown();}
    render(text){return __call('renderMarkdown',{text,engine:'multi',options:this});}
}
class GitHubMarkdown {constructor(){this.autoLinks=true;this.tables=true;this.taskLists=true;this.strikethrough=true;this.tagFilters=false;this.footnotes=true;this.hardBreaks=false;this.safe=true;this.smartQuotes=true;this.sourcePOS=false;this.unsafe=false;this.validateUTF8=false;}static create(){return new GitHubMarkdown();}render(text){return __call('renderMarkdown',{text,engine:'github',options:this});}}
var Markdown=MultiMarkdown;
class HTMLToMarkdown {constructor(){this.emphasisMark='_';this.strongMark='**';this.ulItemMark='*';}static create(){return new HTMLToMarkdown();}process(text){return __call('htmlToMarkdown',{text,options:this});}}
class MustacheTemplate {
    constructor(template=''){this.template=template;this.contentType='html';}
    static createWithTemplate(template){return new MustacheTemplate(template);}
    static createWithPath(path){if(String(path).split('/').includes('..'))throw new Error('Use a path inside the Templates folder.');let t=new MustacheTemplate();t.path=String(path);return t;}
    renderTemplate(name,data){
        if(this.path===undefined)throw new Error('Use createWithPath before renderTemplate.');
        if(String(name).includes('/')||String(name).includes('..'))throw new Error('Use a template name without a path.');
        let fm=FileManager.createCloud(),root='/Library/Templates/'+this.path.replace(/^\/+|\/+$/g,'');
        let partials={};for(let file of fm.listContents(root)){if(file.endsWith('.mustache')){let key=file.split('/').pop().slice(0,-9);partials[key]=fm.readString(file);}}
        if(!Object.prototype.hasOwnProperty.call(partials,name))throw new Error('The Mustache template was not found: '+name);
        return __call('mustache',{template:partials[name],data,partials,contentType:this.contentType});
    }
    static renderTemplate(template,data,partials={}){let t=new MustacheTemplate(template);t.partials=partials;return t.render(data);}
    render(data){return __call('mustache',{template:this.template,data,partials:this.partials||{},contentType:this.contentType});}
}
var alert=message=>__call('alert',{message:String(message)});
var console={log:(...args)=>__call('message',{message:args.map(String).join(' ')}),error:(...args)=>__call('message',{message:args.map(String).join(' ')}),warn:(...args)=>__call('message',{message:args.map(String).join(' ')})};
class Script {constructor(epoch){this.epoch=epoch;}complete(){if(this.epoch===__stepEpoch)__completed=true;}}var __stepEpoch=0,script=new Script(0);
function __beginStep(){__stepEpoch++;__completed=false;__timers=[];script=new Script(__stepEpoch);}
function __endStep(){__timers=[];__stepEpoch++;}
var device=__call('device');
__define(device,'batteryLevel',()=>__call('batteryLevel'));
function require(path){return __require(path);}
function strftime(date,format){return __call('formatDate',{date,format});}
function adjustDate(date,adjustment){return new Date(__call('adjustDate',{date,adjustment}));}
class Autocomplete {
    static getDefault(){return new Autocomplete();}getAll(){return __call('autocomplete',{operation:'get'});}add(value){return __call('autocomplete',{operation:'add',value});}remove(value){return __call('autocomplete',{operation:'remove',value});}
}
var __timers=[],__timerID=0;
function setTimeout(fn,delay=0,...args){let id=++__timerID;__timers.push({id,fn,args,time:Date.now()+delay});return id;}
function clearTimeout(id){__timers=__timers.filter(t=>t.id!==id);}
function __drainTimers(){let now=Date.now(),due=__timers.filter(t=>t.time<=now);__timers=__timers.filter(t=>t.time>now);for(let t of due){if(__completed||__cancelled||__failure)break;t.fn(...t.args);}}
class Alarm {
    constructor(v={}){Object.assign(this,v);if(v.absoluteDate)this.absoluteDate=__date(v.absoluteDate);this.relativeOffset=v.relativeOffset||0;}
    static alarmWithDate(date){return new Alarm({absoluteDate:date});}static alarmWithOffset(seconds){return new Alarm({relativeOffset:seconds});}
}
class Calendar {
    constructor(v={}){Object.assign(this,v);}
    static _get(operation,values={}){let r=__call('eventAPI',{operation,entity:'calendar',...values});return Array.isArray(r)?r.map(v=>new Calendar(v)):r?new Calendar(r):undefined;}
    static default(){return Calendar._get('default');}static find(title){return Calendar._get('find',{title});}
    static findOrCreate(title){return Calendar._get('findOrCreate',{title});}static getAllCalendars(){return Calendar._get('getAll');}
    createEvent(){return new Event({calendar:this});}events(startDate,endDate){return __call('eventAPI',{operation:'events',entity:'calendar',identifier:this.identifier,startDate,endDate}).map(v=>new Event(v));}
    update(){try{Object.assign(this,__call('eventAPI',{operation:'update',entity:'calendar',value:this}));return true;}catch(e){this.lastError=e.message;return false;}}
}
class Event {
    constructor(v={}){Object.assign(this,{title:'',notes:'',location:'',isAllDay:false,alarms:[],startDate:new Date(),endDate:new Date(Date.now()+3600000)},v);for(let k of ['startDate','endDate','creationDate','lastModifiedDate'])if(this[k])this[k]=__date(this[k]);if(v.calendar)this.calendar=new Calendar(v.calendar);this.alarms=this.alarms.map(a=>new Alarm(a));}
    get hasAlarms(){return this.alarms.length>0;}addAlarm(alarm){this.alarms.push(alarm);}removeAlarms(){this.alarms=[];}
    update(){try{Object.assign(this,new Event(__call('eventAPI',{operation:'update',entity:'event',value:this})));this.lastError=undefined;return true;}catch(e){this.lastError=e.message;return false;}}
    edit(){try{let value=__call('eventAPI',{operation:'edit',entity:'event',value:this});if(!value)return false;Object.assign(this,new Event(value));return true;}catch(e){this.lastError=e.message;return false;}}
}
class ReminderList {
    constructor(v={}){Object.assign(this,v);}static _get(operation,values={}){let r=__call('eventAPI',{operation,entity:'list',...values});return Array.isArray(r)?r.map(v=>new ReminderList(v)):r?new ReminderList(r):undefined;}
    static default(){return ReminderList._get('default');}static find(title){return ReminderList._get('find',{title});}static findOrCreate(title){return ReminderList._get('findOrCreate',{title});}static getAllReminderLists(){return ReminderList._get('getAll');}
    get tasks(){return __call('eventAPI',{operation:'tasks',entity:'list',identifier:this.identifier}).map(v=>new Reminder(v));}
    get completeTasks(){return this.tasks.filter(t=>t.isCompleted);}get incompleteTasks(){return this.tasks.filter(t=>!t.isCompleted);}
    createReminder(){return new Reminder({list:this});}
    update(){try{Object.assign(this,__call('eventAPI',{operation:'update',entity:'list',value:this}));return true;}catch(e){this.lastError=e.message;return false;}}
}
class Reminder {
    constructor(v={}){Object.assign(this,{title:'',notes:'',location:'',priority:0,isCompleted:false,alarms:[],dueDateIncludesTime:false,startDateIncludesTime:false},v);for(let k of ['dueDate','startDate','completionDate'])if(this[k])this[k]=__date(this[k]);if(v.list)this.list=new ReminderList(v.list);this.alarms=this.alarms.map(a=>new Alarm(a));}
    get hasAlarms(){return this.alarms.length>0;}addAlarm(alarm){if(!alarm.absoluteDate)return false;this.alarms.push(alarm);return true;}removeAlarms(){this.alarms=[];}
    update(){try{Object.assign(this,new Reminder(__call('eventAPI',{operation:'update',entity:'reminder',value:this})));this.lastError=undefined;return true;}catch(e){this.lastError=e.message;return false;}}
}
class Mail {
    constructor(){this.toRecipients=[];this.ccRecipients=[];this.bccRecipients=[];this.subject='';this.body='';this.isBodyHTML=false;this.sendInBackground=false;this.replyToRecipients=[];this.status='created';}
    get isSent(){return this.status==='sent';}static create(){return new Mail();}send(){let r=__call('composeMail',this);this.status=r.status;return this.status==='sent';}
}
class Message {
    constructor(){this.toRecipients=[];this.subject='';this.body='';this.status='created';}
    get isSent(){return this.status==='sent';}static create(){return new Message();}send(){let r=__call('composeMessage',this);this.status=r.status;return this.status==='sent';}
}
class SpeechVoice {constructor(v={}){Object.assign(this,v);}}
class Speech {
    get allVoices(){return __call('speechVoices').map(v=>new SpeechVoice(v));}
    voices(language){return this.allVoices.filter(v=>v.language===language);}
    speak(text,settings={}){return __call('speak',{text,settings});}
}var speech=new Speech();
class Location {static currentLatitude(){return __call('location').latitude;}static currentLongitude(){return __call('location').longitude;}}
class ModelSessionSchema {
    constructor(){this.fields=[];}static create(){return new this();}
    _add(name,description,type,options){this.fields.push({name,description,type,options});}
}
for(let type of ['Boolean','Int','Number','String'])for(let suffix of ['','Array'])ModelSessionSchema.prototype['add'+type+suffix]=function(name,description,options){this._add(name,description,type.toLowerCase()+suffix,options);};
class SystemLanguageModelSchema extends ModelSessionSchema {}
class ModelSession {
    constructor(){this.sessionID=__call('newUUID');this.mode='onDevice';this.instructions=[];this.toolSets=['drafts','editor'];this.reasoningLevel='';this.temperature=0.5;this.transcript='[]';}
    static create(mode='onDevice'){let v=new ModelSession();v.mode=mode;return v;}
    static availableModes(){return __call('modelModes');}static isAvailable(mode){return ModelSession.availableModes().includes(mode);}
    get isAvailable(){return ModelSession.isAvailable(this.mode);}addInstruction(value){this.instructions.push(value);}addToolSet(value){this.toolSets.push(value);}
    respond(prompt,schema){try{let r=__call('modelRespond',{sessionID:this.sessionID,prompt,schema,mode:this.mode,instructions:this.instructions,temperature:this.temperature,toolSets:this.toolSets});this.transcript=r.transcript;this.lastError=undefined;return r.response;}catch(e){this.lastError=e.message;return undefined;}}
}
class SystemLanguageModel extends ModelSession {
    constructor(tools=[]){super();this.tools=tools;}static create(tools){return new SystemLanguageModel(tools);}enableAllTools(){this.tools=['draft.query','draft.find','draft.create','draft.append','draft.prepend','editor.open','action.run','workspace.find'];}
    respond(prompt,schema){try{let r=__call('modelRespond',{sessionID:this.sessionID,prompt,schema,mode:'onDevice',instructions:this.instructions,temperature:this.temperature,tools:this.tools});this.transcript=r.transcript;this.lastError=undefined;return r.response;}catch(e){this.lastError=e.message;return undefined;}}
}
