format 75

classcanvas 128056 class_ref 128440 // Parkings
  draw_all_relations default hide_attributes default hide_operations default hide_getset_operations default show_members_full_definition default show_members_visibility default show_members_stereotype default show_members_context default show_members_multiplicity default show_members_initialization default show_attribute_modifiers default member_max_width 0 show_parameter_dir default show_parameter_name default package_name_in_tab default class_drawing_mode default drawing_language default show_context_mode default auto_label_position default show_relation_modifiers default show_relation_visibility default show_infonote default shadow default show_stereotype_properties default
  xyz 74 70 2000
end
classcanvas 128184 class_ref 128568 // Places
  draw_all_relations default hide_attributes default hide_operations default hide_getset_operations default show_members_full_definition default show_members_visibility default show_members_stereotype default show_members_context default show_members_multiplicity default show_members_initialization default show_attribute_modifiers default member_max_width 0 show_parameter_dir default show_parameter_name default package_name_in_tab default class_drawing_mode default drawing_language default show_context_mode default auto_label_position default show_relation_modifiers default show_relation_visibility default show_infonote default shadow default show_stereotype_properties default
  xyz 181 130 2000
end
classcanvas 128568 class_ref 128696 // Voitures
  draw_all_relations default hide_attributes default hide_operations default hide_getset_operations default show_members_full_definition default show_members_visibility default show_members_stereotype default show_members_context default show_members_multiplicity default show_members_initialization default show_attribute_modifiers default member_max_width 0 show_parameter_dir default show_parameter_name default package_name_in_tab default class_drawing_mode default drawing_language default show_context_mode default auto_label_position default show_relation_modifiers default show_relation_visibility default show_infonote default shadow default show_stereotype_properties default
  xyz 355 129 2005
end
classcanvas 128696 class_ref 128824 // Marques
  draw_all_relations default hide_attributes default hide_operations default hide_getset_operations default show_members_full_definition default show_members_visibility default show_members_stereotype default show_members_context default show_members_multiplicity default show_members_initialization default show_attribute_modifiers default member_max_width 0 show_parameter_dir default show_parameter_name default package_name_in_tab default class_drawing_mode default drawing_language default show_context_mode default auto_label_position default show_relation_modifiers default show_relation_visibility default show_infonote default shadow default show_stereotype_properties default
  xyz 449 79 2005
end
packagecanvas 129080 
  package_ref 128440 // Vehicules
    xyzwh 335 34 2000 217 165
end
packagecanvas 129336 
  package_ref 128312 // Parkings
    xyzwh 61 29 2000 187 169
end
relationcanvas 128952 relation_ref 128312 // <unidirectional association>
  from ref 128184 z 2006 to ref 128568
  no_role_a no_role_b
  no_multiplicity_a no_multiplicity_b
end
simplerelationcanvas 129464 simplerelation_ref 128056
  from ref 129336 z 2001 to ref 129080
end
end
