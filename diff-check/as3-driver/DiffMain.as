// diff-check/as3-driver/DiffMain.as -- AS3 side of the shared layout differential.
//
// Reads the FROZEN shared spec `asaotui/diff-check/spec/cases.txt`, drives
// asaot.ui.as3.As3LayoutEngine through it, and prints one `GOT <name> l t w h`
// line per `check` directive (4-decimal, spec order). A sibling C driver reads
// the SAME file, drives Yoga, and prints the SAME format; the two outputs are
// diffed -- the GOT lines are the contract, the `check` expectations are only a
// per-driver self-test (EPS = 0.01). Any mismatch -> non-zero exit (`throw`).
//
// FILE READING: runtime via flash.filesystem.File + FileStream (route 1), NOT a
// build-time generated literal table. Rationale: it is the faithful "same one
// file" -- the C side and this side open the identical bytes, so the spec can be
// edited without recompiling either driver. This compiles and runs on our own
// AOT (see as3-driver/Probe.as): File.nativePath / exists / FileStream.open /
// readUTFBytes / bytesAvailable / close are all supported.
//
// WHY A SINGLE ENGINE INSTANCE ACROSS ALL CASES: createConfig() is called on
// every `engine` line and createNode() reads its default flex-direction off the
// config object (not off engine state), so reusing one As3LayoutEngine instance
// is equivalent to CheckMain's per-case `new As3LayoutEngine()`.
import asaot.ui.LayoutEngine;
import asaot.ui.LayoutConstants;
import asaot.ui.as3.As3LayoutEngine;
import flash.filesystem.File;
import flash.filesystem.FileStream;
import flash.filesystem.FileMode;

var EPS:Number = 0.01;
var eng:LayoutEngine = new As3LayoutEngine();
var currentCfg:Object = eng.createConfig(0, true);

// Node registry: ids are globally unique, so parallel arrays + linear find are
// unambiguous (and sidestep any dynamic-string-key subtleties).
var nodeIds:Array = [];
var nodes:Array = [];
// Per-parent child count, so insertChild gets the appearance ordinal.
var parentIds:Array = [];
var parentCounts:Array = [];

// Recorded `check` rows, evaluated after the whole file is read.
var ckName:Array = [];
var ckId:Array = [];
var ckL:Array = [];
var ckT:Array = [];
var ckW:Array = [];
var ckH:Array = [];

function f4(x:Number):String { return x.toFixed(4); }

function registerNode(id:String, n:Object):void
{
    nodeIds.push(id);
    nodes.push(n);
}

function nodeIndex(id:String):int
{
    var i:int;
    for (i = 0; i < nodeIds.length; i++) { if (String(nodeIds[i]) == id) return i; }
    return -1;
}

function getNode(id:String):Object
{
    var i:int = nodeIndex(id);
    if (i < 0) throw new Error('DiffMain: unknown node id: ' + id);
    return nodes[i];
}

function childSeq(parentId:String):int
{
    var i:int;
    for (i = 0; i < parentIds.length; i++)
    {
        if (String(parentIds[i]) == parentId)
        {
            var v:int = int(parentCounts[i]);
            parentCounts[i] = v + 1;
            return v;
        }
    }
    parentIds.push(parentId);
    parentCounts.push(1);
    return 0;
}

// ---- token / enum mapping -------------------------------------------------

function dirOf(s:String):int
{
    if (s == 'row') return LayoutConstants.FLEX_DIR_ROW;
    if (s == 'column') return LayoutConstants.FLEX_DIR_COLUMN;
    if (s == 'row-reverse') return LayoutConstants.FLEX_DIR_ROW_REVERSE;
    if (s == 'column-reverse') return LayoutConstants.FLEX_DIR_COLUMN_REVERSE;
    throw new Error('DiffMain: bad dir: ' + s);
}

function axisOf(s:String):int
{
    if (s == 'w') return LayoutConstants.AXIS_WIDTH;
    if (s == 'h') return LayoutConstants.AXIS_HEIGHT;
    throw new Error('DiffMain: bad axis: ' + s);
}

function unitOf(s:String):int
{
    if (s == 'point') return LayoutConstants.UNIT_POINT;
    if (s == 'percent') return LayoutConstants.UNIT_PERCENT;
    if (s == 'undefined') return LayoutConstants.UNIT_UNDEFINED;
    if (s == 'auto') return LayoutConstants.UNIT_AUTO;
    throw new Error('DiffMain: bad unit: ' + s);
}

function dirTokenOf(s:String):int
{
    if (s == 'ltr') return LayoutConstants.DIR_LTR;
    if (s == 'rtl') return LayoutConstants.DIR_RTL;
    throw new Error('DiffMain: bad writing direction: ' + s);
}

function wrapOf(s:String):int
{
    if (s == 'nowrap') return LayoutConstants.WRAP_NO_WRAP;
    if (s == 'wrap') return LayoutConstants.WRAP_WRAP;
    if (s == 'wrap-reverse') return LayoutConstants.WRAP_WRAP_REVERSE;
    throw new Error('DiffMain: bad wrap: ' + s);
}

function justifyOf(s:String):int
{
    if (s == 'flex-start') return LayoutConstants.JUSTIFY_FLEX_START;
    if (s == 'center') return LayoutConstants.JUSTIFY_CENTER;
    if (s == 'flex-end') return LayoutConstants.JUSTIFY_FLEX_END;
    if (s == 'space-between') return LayoutConstants.JUSTIFY_SPACE_BETWEEN;
    if (s == 'space-around') return LayoutConstants.JUSTIFY_SPACE_AROUND;
    if (s == 'space-evenly') return LayoutConstants.JUSTIFY_SPACE_EVENLY;
    throw new Error('DiffMain: bad justify: ' + s);
}

function alignOf(s:String, allowAuto:Boolean):int
{
    if (s == 'auto' && allowAuto) return LayoutConstants.ALIGN_AUTO;
    if (s == 'flex-start') return LayoutConstants.ALIGN_FLEX_START;
    if (s == 'center') return LayoutConstants.ALIGN_CENTER;
    if (s == 'flex-end') return LayoutConstants.ALIGN_FLEX_END;
    if (s == 'stretch') return LayoutConstants.ALIGN_STRETCH;
    if (s == 'space-between') return LayoutConstants.ALIGN_SPACE_BETWEEN;
    if (s == 'space-around') return LayoutConstants.ALIGN_SPACE_AROUND;
    throw new Error('DiffMain: bad align: ' + s);
}

function posTypeOf(s:String):int
{
    if (s == 'relative') return LayoutConstants.POSITION_RELATIVE;
    if (s == 'absolute') return LayoutConstants.POSITION_ABSOLUTE;
    if (s == 'static') return LayoutConstants.POSITION_STATIC;
    throw new Error('DiffMain: bad position type: ' + s);
}

function overflowOf(s:String):int
{
    if (s == 'visible') return LayoutConstants.OVERFLOW_VISIBLE;
    if (s == 'hidden') return LayoutConstants.OVERFLOW_HIDDEN;
    if (s == 'scroll') return LayoutConstants.OVERFLOW_SCROLL;
    throw new Error('DiffMain: bad overflow: ' + s);
}

function edgePad(s:String):int
{
    if (s == 'all') return LayoutConstants.EDGE_ALL;
    if (s == 'h') return LayoutConstants.EDGE_HORIZONTAL;
    if (s == 'v') return LayoutConstants.EDGE_VERTICAL;
    if (s == 'top') return LayoutConstants.EDGE_TOP;
    if (s == 'right') return LayoutConstants.EDGE_RIGHT;
    if (s == 'bottom') return LayoutConstants.EDGE_BOTTOM;
    if (s == 'left') return LayoutConstants.EDGE_LEFT;
    if (s == 'start') return LayoutConstants.EDGE_START;
    if (s == 'end') return LayoutConstants.EDGE_END;
    throw new Error('DiffMain: bad pad edge: ' + s);
}

function edgeBorder(s:String):int
{
    if (s == 'all') return LayoutConstants.EDGE_ALL;
    if (s == 'top') return LayoutConstants.EDGE_TOP;
    if (s == 'right') return LayoutConstants.EDGE_RIGHT;
    if (s == 'bottom') return LayoutConstants.EDGE_BOTTOM;
    if (s == 'left') return LayoutConstants.EDGE_LEFT;
    if (s == 'start') return LayoutConstants.EDGE_START;
    if (s == 'end') return LayoutConstants.EDGE_END;
    throw new Error('DiffMain: bad border edge: ' + s);
}

function gutterOf(s:String):int
{
    if (s == 'row') return LayoutConstants.GUTTER_ROW;
    if (s == 'col' || s == 'column') return LayoutConstants.GUTTER_COLUMN;
    if (s == 'all') return LayoutConstants.GUTTER_ALL;
    throw new Error('DiffMain: bad gutter: ' + s);
}

// Whitespace-split one line; '#' starts a comment; blank lines yield [].
function tokens(line:String):Array
{
    var out:Array = [];
    var cur:String = '';
    var i:int = 0;
    var n:int = line.length;
    while (i < n)
    {
        var c:int = line.charCodeAt(i);
        if (c == 35) break; // '#'
        if (c == 32 || c == 9 || c == 13 || c == 10)
        {
            if (cur.length > 0) { out.push(cur); cur = ''; }
        }
        else
        {
            cur = cur + line.charAt(i);
        }
        i++;
    }
    if (cur.length > 0) out.push(cur);
    return out;
}

function splitLines(text:String):Array
{
    var out:Array = [];
    var cur:String = '';
    var i:int = 0;
    var n:int = text.length;
    while (i < n)
    {
        var c:int = text.charCodeAt(i);
        if (c == 10) { out.push(cur); cur = ''; }
        else { cur = cur + text.charAt(i); }
        i++;
    }
    if (cur.length > 0) out.push(cur);
    return out;
}

// ---- spec location (runtime file read) ------------------------------------

// Try the spec relative to the as3compiler/ run dir first, then a few other
// plausible working directories, so the driver is not brittle to CWD.
function findSpec():String
{
    var cands:Array = [
        '../asaotui/diff-check/spec/cases.txt',
        'asaotui/diff-check/spec/cases.txt',
        'spec/cases.txt',
        'cases.txt'
    ];
    var i:int;
    for (i = 0; i < cands.length; i++)
    {
        var f:File = new File(String(cands[i]));
        if (f.exists) return String(cands[i]);
    }
    throw new Error('DiffMain: cases.txt not found (tried: ' + cands.join(', ') + ')');
}

function readSpec(path:String):String
{
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.READ);
    var all:String = fs.readUTFBytes(fs.bytesAvailable);
    fs.close();
    return all;
}

// ---- drive the spec -------------------------------------------------------

var specPath:String = findSpec();
var lines:Array = splitLines(readSpec(specPath));
var li:int;
for (li = 0; li < lines.length; li++)
{
    var tk:Array = tokens(String(lines[li]));
    if (tk.length == 0) continue;
    var d:String = String(tk[0]);

    if (d == 'engine')
    {
        var web:Boolean = (String(tk[1]) == 'web');
        currentCfg = eng.createConfig(0, web);
    }
    else if (d == 'node')
    {
        var id:String = String(tk[1]);
        var pid:String = String(tk[2]);
        var nn:Object = eng.createNode(currentCfg);
        registerNode(id, nn);
        if (pid != '-1')
        {
            eng.insertChild(getNode(pid), nn, childSeq(pid));
        }
    }
    else if (d == 'root')
    {
        // calculate() runs IMMEDIATELY, per the frozen spec. The trailing
        // ltr|rtl token is optional (absent == ltr), keeping old lines valid.
        var rdir:int = (tk.length >= 5) ? dirTokenOf(String(tk[4])) : LayoutConstants.DIR_LTR;
        eng.calculate(getNode(String(tk[1])), parseFloat(String(tk[2])),
            parseFloat(String(tk[3])), rdir);
    }
    else if (d == 'dir')
    {
        eng.setFlexDirection(getNode(String(tk[1])), dirOf(String(tk[2])));
    }
    else if (d == 'size')
    {
        eng.setSize(getNode(String(tk[1])), axisOf(String(tk[2])),
            parseFloat(String(tk[3])), unitOf(String(tk[4])));
    }
    else if (d == 'minmax')
    {
        var isMax:Boolean = (String(tk[3]) == 'max');
        eng.setMinMax(getNode(String(tk[1])), axisOf(String(tk[2])), isMax,
            parseFloat(String(tk[4])), unitOf(String(tk[5])));
    }
    else if (d == 'pad')
    {
        var punit:int = (tk.length >= 5) ? unitOf(String(tk[4])) : LayoutConstants.UNIT_POINT;
        eng.setPadding(getNode(String(tk[1])), edgePad(String(tk[2])),
            parseFloat(String(tk[3])), punit);
    }
    else if (d == 'border')
    {
        eng.setBorder(getNode(String(tk[1])), edgeBorder(String(tk[2])),
            parseFloat(String(tk[3])));
    }
    else if (d == 'gap')
    {
        var gunit:int = (tk.length >= 5) ? unitOf(String(tk[4])) : LayoutConstants.UNIT_POINT;
        eng.setGap(getNode(String(tk[1])), gutterOf(String(tk[2])),
            parseFloat(String(tk[3])), gunit);
    }
    else if (d == 'margin')
    {
        var munit:int = (tk.length >= 5) ? unitOf(String(tk[4])) : LayoutConstants.UNIT_POINT;
        eng.setMargin(getNode(String(tk[1])), edgePad(String(tk[2])),
            parseFloat(String(tk[3])), munit);
    }
    else if (d == 'inset')
    {
        var iunit:int = (tk.length >= 5) ? unitOf(String(tk[4])) : LayoutConstants.UNIT_POINT;
        eng.setPosition(getNode(String(tk[1])), edgePad(String(tk[2])),
            parseFloat(String(tk[3])), iunit);
    }
    else if (d == 'pos')
    {
        eng.setPositionType(getNode(String(tk[1])), posTypeOf(String(tk[2])));
    }
    else if (d == 'overflow')
    {
        eng.setOverflow(getNode(String(tk[1])), overflowOf(String(tk[2])));
    }
    else if (d == 'wrap')
    {
        eng.setFlexWrap(getNode(String(tk[1])), wrapOf(String(tk[2])));
    }
    else if (d == 'justify')
    {
        eng.setJustifyContent(getNode(String(tk[1])), justifyOf(String(tk[2])));
    }
    else if (d == 'align')
    {
        eng.setAlignItems(getNode(String(tk[1])), alignOf(String(tk[2]), false));
    }
    else if (d == 'alignself')
    {
        eng.setAlignSelf(getNode(String(tk[1])), alignOf(String(tk[2]), true));
    }
    else if (d == 'aligncontent')
    {
        eng.setAlignContent(getNode(String(tk[1])), alignOf(String(tk[2]), false));
    }
    else if (d == 'flex')
    {
        eng.setFlex(getNode(String(tk[1])), parseFloat(String(tk[2])),
            parseFloat(String(tk[3])), parseFloat(String(tk[4])), unitOf(String(tk[5])));
    }
    else if (d == 'boxsizing')
    {
        if (String(tk[2]) == 'content')
            eng.setBoxSizing(getNode(String(tk[1])), LayoutConstants.BOX_SIZING_CONTENT_BOX);
        else
            eng.setBoxSizing(getNode(String(tk[1])), LayoutConstants.BOX_SIZING_BORDER_BOX);
    }
    else if (d == 'check')
    {
        // Recorded now, evaluated at end-of-file (a later `root` may still
        // recalculate a node referenced by an earlier check).
        ckName.push(String(tk[1]));
        ckId.push(String(tk[2]));
        ckL.push(parseFloat(String(tk[3])));
        ckT.push(parseFloat(String(tk[4])));
        ckW.push(parseFloat(String(tk[5])));
        ckH.push(parseFloat(String(tk[6])));
    }
    else
    {
        throw new Error('DiffMain: unknown directive at spec line ' + (li + 1) + ': ' + d);
    }
}

// ---- evaluate checks (spec order) -----------------------------------------

var fails:int = 0;
var nchk:int = ckName.length;
var ci:int;
for (ci = 0; ci < nchk; ci++)
{
    var nm:String = String(ckName[ci]);
    var node:Object = getNode(String(ckId[ci]));
    var o:Array = [];
    eng.layoutGet(node, o);
    var ol:Number = Number(o[0]);
    var ot:Number = Number(o[1]);
    var ow:Number = Number(o[2]);
    var oh:Number = Number(o[3]);
    var wl:Number = Number(ckL[ci]);
    var wt:Number = Number(ckT[ci]);
    var ww:Number = Number(ckW[ci]);
    var wh:Number = Number(ckH[ci]);

    trace('GOT ' + nm + ' ' + f4(ol) + ' ' + f4(ot) + ' ' + f4(ow) + ' ' + f4(oh));

    var ok:Boolean = Math.abs(ol - wl) <= EPS && Math.abs(ot - wt) <= EPS
        && Math.abs(ow - ww) <= EPS && Math.abs(oh - wh) <= EPS;
    var detail:String = nm + ' got(' + f4(ol) + ',' + f4(ot) + ',' + f4(ow) + ',' + f4(oh)
        + ') want(' + f4(wl) + ',' + f4(wt) + ',' + f4(ww) + ',' + f4(wh) + ')';
    if (ok) trace('  OK   ' + detail);
    else { fails++; trace('  FAIL ' + detail); }
}

trace('---- ' + nchk + ' checks, ' + fails + ' failures ----');
if (fails > 0) throw new Error('diff-check: ' + fails + ' of ' + nchk + ' FAILED');
