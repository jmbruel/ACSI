format 75

classinstance 128056 class_ref 135352 // Client
  name ""   xyz 60 4 2000 life_line_z 2000
classinstance 128184 class_ref 135480 // System
  name ""   xyz 226 6 2000 life_line_z 2000
durationcanvas 128312 classinstance_ref 128056 // :Client
  xyzwh 73 71 2010 11 80
end
durationcanvas 128440 classinstance_ref 128184 // :System
  xyzwh 249 71 2010 11 80
end
durationcanvas 129208 classinstance_ref 128056 // :Client
  xyzwh 73 178 2010 11 50
end
durationcanvas 129336 classinstance_ref 128184 // :System
  xyzwh 249 178 2010 11 50
end
msg 128568 synchronous
  from durationcanvas_ref 128312
  to durationcanvas_ref 128440
  yz 71 2015 explicitmsg "demanderTrainPour(ville)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 98 57
msg 129080 return
  from durationcanvas_ref 128440
  to durationcanvas_ref 128312
  yz 140 2020 explicitmsg "listeTrainPour(ville)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 115 126
msg 129464 synchronous
  from durationcanvas_ref 129208
  to durationcanvas_ref 129336
  yz 178 2015 explicitmsg "choixTrain(t1)"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 129 164
msg 129592 return
  from durationcanvas_ref 129336
  to durationcanvas_ref 129208
  yz 214 2015 explicitmsg "reservationOK()"
  show_full_operations_definition default drawing_language default show_context_mode default
  label_xy 122 200
end
