var qaIncludedObservations = [];
function qaIncludedObserve(stage) {
    var present = Object.prototype.hasOwnProperty.call(context.configuredValues, 'label');
    var value = context.configuredValues.label;
    qaIncludedObservations.push([stage, typeof value, present ? value : null]);
}
function qaIncludedFinish() {
    editor.setText(JSON.stringify(qaIncludedObservations));
    draft.update();
}
