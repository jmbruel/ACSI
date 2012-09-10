format 75

classinstance 128056 class_ref 135352 // Client
  name ""   xyz 109 4 2000 life_line_z 2000
classinstance 128184 class_ref 135608 // Screen
  name ""   xyz 267 4 2000 life_line_z 2000
classinstance 128312 class_ref 135736 // CtrlResa
  name ""   xyz 465 4 2000 life_line_z 2000
classinstance 128440 class_ref 135864 // Trains
  name ""   xyz 616 4 2000 life_line_z 2000
classinstance 130104 class_ref 135864 // Trains
  name "t1"   xyz 720 4 2005 life_line_z 2000
durationcanvas 128568 classinstance_ref 128056 // :Client
  xyzwh 122 60 2010 11 129
end
durationcanvas 128696 classinstance_ref 128184 // :Screen
  xyzwh 288 52 2010 11 96
end
durationcanvas 128952 classinstance_ref 128312 // :CtrlResa
  xyzwh 492 81 2010 11 50
end
durationcanvas 129208 classinstance_ref 128184 // :Screen
  xyzwh 288 69 2010 11 62
end
durationcanvas 129464 classinstance_ref 128440 // :Trains
  xyzwh 635 95 2010 11 25
end
durationcanvas 129848 classinstance_ref 128184 // :Screen
  xyzwh 288 158 2010 11 75
  overlappingdurationcanvas 130872
    xyzwh 294 202 2020 11 25
  end
end
durationcanvas 130232 classinstance_ref 128312 // :CtrlResa
  xyzwh 492 170 2010 11 44
end
durationcanvas 130488 classinstance_ref 130104 // t1:Trains
  xyzwh 743 181 2010 11 25
end
msg 128824 synchronous
  from durationcanvas_ref 128568
  to durationcanvas_ref 128696
  yz 61 2015 explicitmsg "demanderTrainPour(ville)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 139 46
msg 129080 synchronous
  from durationcanvas_ref 128696
  to durationcanvas_ref 128952
  yz 82 2015 explicitmsg "getTrainsFromTo(Toulouse,ville)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 309 67
msg 129336 return
  from durationcanvas_ref 128952
  to durationcanvas_ref 129208
  yz 120 2015 unspecifiedmsg
  show_full_operations_definition default drawing_language default show_context_mode default
msg 129592 synchronous
  from durationcanvas_ref 128952
  to durationcanvas_ref 129464
  yz 95 2015 explicitmsg "getInfos"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 547 81
msg 129720 return
  from durationcanvas_ref 129464
  to durationcanvas_ref 128952
  yz 108 2020 unspecifiedmsg
  show_full_operations_definition default drawing_language default show_context_mode default
msg 129976 synchronous
  from durationcanvas_ref 128568
  to durationcanvas_ref 129848
  yz 158 2015 explicitmsg "choixTrain(t1)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 173 144
msg 130360 synchronous
  from durationcanvas_ref 129848
  to durationcanvas_ref 130232
  yz 171 2020 explicitmsg "setResaTrain(t1)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 348 157
msg 130616 synchronous
  from durationcanvas_ref 130232
  to durationcanvas_ref 130488
  yz 182 2015 unspecifiedmsg
  show_full_operations_definition default drawing_language default show_context_mode default
reflexivemsg 131000 synchronous
  to durationcanvas_ref 130872
  yz 202 2025 explicitmsg "afficherResaOK"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 332 206
end
