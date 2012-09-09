format 75

classcanvas 128056 class_ref 128056 // Visiteur
  class_drawing_mode default show_context_mode default show_stereotype_properties default
  xyz 108 65 2000
end
usecasecanvas 128184 usecase_ref 128056 // visiter site web
  xyzwh 313 80 3005 64 32 label_xy 303 112
end
classcanvas 128440 class_ref 128184 // admin
  class_drawing_mode default show_context_mode default show_stereotype_properties default
  xyz 109 191 2000
end
usecasecanvas 128568 usecase_ref 128184 // administrer site web
  xyzwh 342 206 3005 64 32 label_xy 318 238
end
line 128312 --->
  from ref 128056 z 3006 to ref 128184
line 128696 --->
  from ref 128440 z 3006 to ref 128568
relationcanvas 128952 relation_ref 128056 // <generalisation>
  from ref 128440 z 2001 to ref 128056
  no_role_a no_role_b
  no_multiplicity_a no_multiplicity_b
end
end
