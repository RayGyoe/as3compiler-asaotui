// G9Aot.as -- our AOT arm: SAME G9Cases.run(), printed to stdout.
// Top-level statements (our AOT takes them as the entry point); AIR needs a
// document class, so the AIR arm uses G9Air.as instead. Case code is shared.
import G9Cases;

trace("AOT " + G9Cases.run() + "");
