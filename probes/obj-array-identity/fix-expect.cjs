// One-shot: clear the G14 deviation list in the probe's expect.json.
'use strict';
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, 'expect.json');
const raw = fs.readFileSync(FILE, 'utf8');
const j = JSON.parse(raw);

j.knownAotDeviations = [];
j._knownAotDeviations_note =
  'EMPTY since 阶段二百五十三 (v0.4.217) -- the compiler now answers all 26 cells exactly like AIR. '
  + 'The eight former deviations were: 1 = "is Array" constant-folded to false; 3/12/19/21/26 = '
  + '"as_is(<array ptr>, &SomeClass_vt)" read the array header\'s first word as a vtable -> SIGSEGV; '
  + '15 = "as Array" -> NULL; 16 = "length" -> undefined. FIX (src/emit.ts + src/runtime.ts): an '
  + 'Object-typed receiver now takes the SAME runtime dispatch a "*" receiver already took '
  + '(as_obj_is_array / as_obj_as_array / as_obj_class_of for is+as+constructor, as_dyn_call -> '
  + 'as_arr_call for methods, as_dyn_get -> as_array_key_get for index/length, as_dyn_del for delete, '
  + 'as_obj_to_str / as_obj_to_number for String()/Number(), as_obj_to_value for for-each), and '
  + 'as_is / as_iface_lookup refuse to read a first word that is not a vtable (as_has_vtable).';

fs.writeFileSync(FILE, JSON.stringify(j, null, 2) + '\n');
console.log('knownAotDeviations =', JSON.stringify(j.knownAotDeviations));
console.log('note length =', j._knownAotDeviations_note.length);