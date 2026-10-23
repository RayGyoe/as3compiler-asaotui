// demo/DemoView.as -- the demo's view (Deliverable 2), shared by both drivers.
//
// Layout uses ONLY the surface the pure-AS3 engine implements (row/column,
// explicit point/percent sizes, padding, border, gap, flex grow/shrink/basis,
// min/max, box-sizing). It deliberately uses NO margin/justify/align/wrap/
// position, because another worker owns those setters and they are not yet part
// of the frozen subset. Nothing here needs them: a vertical stack of full-width
// rows needs no centring, and where a centred label IS wanted (the button) we
// centre the TextField inside its own box in paint (UiNode.paintSelf), not via
// the layout engine.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.View;
    import asaot.ui.bindTo;
    import asaot.ui.button;
    import asaot.ui.checkbox;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public class DemoView extends View
    {
        // ---- styles, built ONCE (design doc section 2.4: a style constant is
        // created at class-load time so `render` hands the resolver the same
        // pointer every frame and the identity test skips it entirely).
        private static const PAGE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column",
            padding: 28,
            gap: 14,
            size: [Length.pct(1), Length.pct(1)],
            background: 0xFFFFFFFF
        });
        private static const TITLE:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 26, fontWeight: "bold", color: 0x111827 }
        });
        private static const SUB:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, color: 0x6B7280 }
        });
        private static const CARD:StyleRefinement = StyleRefinement.from({
            flexDirection: "column",
            padding: 18,
            gap: 12,
            size: [Length.pct(1), null],
            background: 0xF9FAFB,
            border: 1,
            borderColor: 0xE5E7EB,
            cornerRadii: 12
        });
        private static const FIELD:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(42)],
            text: { fontSize: 14, color: 0x111827 }
        });
        private static const REMEMBER_ROW:StyleRefinement = StyleRefinement.from({
            flexDirection: "row",
            gap: 10,
            size: [Length.pct(1), Length.px(30)]
        });
        private static const SIGNIN:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(46)],
            background: 0x2563EB,
            border: 1,
            borderColor: 0x1D4ED8,
            cornerRadii: 8,
            text: { fontSize: 15, fontWeight: "bold", color: 0xFFFFFF }
        });
        private static const STATUS:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, color: 0x2563EB }
        });

        public var model:DemoModel;

        public function DemoView(m:DemoModel):void
        {
            super();
            this.model = m;
        }

        override public function render():Node
        {
            // Pure description. The status line is read from the model here, so a
            // model notify re-renders exactly this string; the two text fields and
            // the checkbox write their edits back through their bindings.
            return column({ key: "root", style: PAGE, ariaName: "Sign in page" }, [
                text("asaot.ui", { key: "title", style: TITLE, ariaName: "Product" }),
                text("A GPUI-inspired AS3 UI toolkit, laid out by the pure-AS3 engine.",
                    { key: "sub", style: SUB, ariaName: "Tagline" }),
                column({ key: "card", style: CARD, ariaName: "Credentials" }, [
                    textField({
                        key: "account", style: FIELD, ariaName: "Account",
                        placeholder: "Account or email", value: bindTo(this.model, "account")
                    }),
                    textField({
                        key: "password", style: FIELD, ariaName: "Password",
                        placeholder: "Password", password: true, value: bindTo(this.model, "password")
                    }),
                    row({ key: "rememberRow", style: REMEMBER_ROW, ariaName: "Options" }, [
                        checkbox({
                            key: "remember", ariaName: "Remember me",
                            label: "Keep me signed in", checked: bindTo(this.model, "remember")
                        })
                    ]),
                    button({
                        key: "signin", style: SIGNIN, ariaName: "Sign in",
                        label: "Sign in", onClick: this.signIn
                    })
                ]),
                text(this.model.status, { key: "status", style: STATUS, ariaName: "Status" })
            ]);
        }

        // Runs on a real mouse click in the window; it mutates the model and
        // raises ONE dirty bit -- exactly the section 5.1
        // notify -> invalidate -> repaint chain.
        private function signIn():void
        {
            var who:String = this.model.account;
            if (who == null || who.length == 0) who = "(no account)";
            this.model.status = "signing in as " + who + "...";
            this.model.notify(Dirty.VALUE);
        }
    }
}