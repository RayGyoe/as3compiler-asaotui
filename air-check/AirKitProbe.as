// air-check/AirKitProbe.as -- compile the WHOLE asaot.ui toolkit with the real AIR
// reference compiler, without running anything.
//
// WHY: our AOT accepts a superset of what mxmlc accepts -- it tolerates
// top-level-script .as files (mxmlc demands a class named after the file), it
// resolves some types with no explicit import, and it never phrases a rejection
// the way mxmlc does. So "our compiler built it" is NOT evidence that the
// toolkit is portable AS3. Only mxmlc is. This file is the thing that turns
// "the toolkit is pure AS3" from an intention into a measurement.
//
// WHAT IT DOES: names every public type of the toolkit in a declaration and
// calls every public factory once, so mxmlc must resolve, type-check and compile
// all of them. It is not a test of behaviour -- CheckUi.as (run under our AOT)
// and ui-demo (run in a real window) cover that. This is purely the
// "does the AIR compiler accept this source" question.
//
// RUN:
//   cd asaotui
//   AIRSDK_HOME=<AIR SDK root> node tools/mxmlc-check.cjs \
//     --root air-check/AirKitProbe.as --src kit --src seam --out air-check/air-kit.swf
//
// KEEPING IT HONEST: every name below must correspond to a real public symbol.
// If a type is renamed or removed the compile breaks, which is the desired
// behaviour -- a stale probe that still compiles is a silent lie.
package
{
    import asaot.ui.Binding;
    import asaot.ui.Box;
    import asaot.ui.Button;
    import asaot.ui.Checkbox;
    import asaot.ui.Control;
    import asaot.ui.Dirty;
    import asaot.ui.Element;
    import asaot.ui.ElementState;
    import asaot.ui.Node;
    import asaot.ui.Observable;
    import asaot.ui.Reconciler;
    import asaot.ui.Subscription;
    import asaot.ui.Text;
    import asaot.ui.TextInput;
    import asaot.ui.Theme;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import asaot.ui.View;

    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.TextStyle;

    // the layout seam the toolkit is built on
    import asaot.ui.LayoutConstants;
    import asaot.ui.LayoutEngine;
    import asaot.ui.as3.As3LayoutEngine;

    // package-level factories (section 4.2) -- importing them forces Factories.as
    // to be compiled by AIR as well, which is where the "package-level function"
    // form itself gets checked.
    import asaot.ui.box;
    import asaot.ui.row;
    import asaot.ui.column;
    import asaot.ui.text;
    import asaot.ui.label;
    import asaot.ui.button;
    import asaot.ui.textField;
    import asaot.ui.checkbox;

    public class AirKitProbe
    {
        // One declaration per public type: mxmlc has to resolve each one.
        private var t01:Binding;
        private var t02:Box;
        private var t03:Button;
        private var t04:Checkbox;
        private var t05:Control;
        private var t06:Element;
        private var t07:ElementState;
        private var t08:Node;
        private var t09:Observable;
        private var t10:Reconciler;
        private var t11:Subscription;
        private var t12:Text;
        private var t13:TextInput;
        private var t14:Theme;
        private var t15:UiApp;
        private var t16:UiNode;
        private var t17:View;
        private var t18:Corners;
        private var t19:Edges;
        private var t20:Fill;
        private var t21:Length;
        private var t22:Size;
        private var t23:Style;
        private var t24:StyleRefinement;
        private var t25:TextStyle;
        private var t26:LayoutConstants;
        private var t27:LayoutEngine;
        private var t28:As3LayoutEngine;

        // Constants and the enum-ish surface: reading them proves the static
        // members exist with the right types.
        public static const FLEX_DIR_ROW:int = LayoutConstants.FLEX_DIR_ROW;
        public static const JUSTIFY_CENTER:int = LayoutConstants.JUSTIFY_CENTER;
        public static const UNIT_POINT:int = LayoutConstants.UNIT_POINT;
        public static const DIR_LTR:int = LayoutConstants.DIR_LTR;
        public static const M_MEASURE:int = Dirty.M_MEASURE;
        public static const M_ARRANGE:int = Dirty.M_ARRANGE;
        public static const M_PAINT:int = Dirty.M_PAINT;
        public static const M_ALL:int = Dirty.ALL;

        public function AirKitProbe():void
        {
            // Build one description tree through the public factories, so their
            // signatures (not just their file's syntax) are checked by AIR.
            var tree:Node = column({ "gap": 8 }, [
                text("asaot.ui"),
                row({ "gap": 4 }, [
                    button({ "label": "OK" }),
                    label("label"),
                    checkbox({ "label": "check" })
                ]),
                textField({ "placeholder": "type here" }),
                box({})
            ]);
            this.t08 = tree;

            // The engine behind the seam is pure AS3, so AIR can instantiate it.
            this.t28 = new As3LayoutEngine();
            this.t27 = this.t28;

            // The style layer is data, so a refinement can be built with no engine.
            this.t24 = new StyleRefinement();
            this.t23 = new Style();
        }
    }
}