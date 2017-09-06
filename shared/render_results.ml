#! /usr/bin/env ocaml

(* ASSUMPTIONS:
   - the 1-st command line argument (working directory):
     - designates an existing readable directory
     - which contains *.time and *.perf files produced by bench.sh script
   - the 2-nd command line argument (number of iterations):
     - is a positive integer
   - the 3-rd command line argument (minimal user time):
     - is a positive floating point number
   - the 4-th command line argument determines the name of the column according to which the resulting table will be sorted.
     Valid values are:
     - package_name
     - user_time_pdiff
   - the rest of the command line-arguments
     - are names of benchamarked Coq OPAM packages for which bench.sh script generated *.time and *.perf files
 *)

#use "topfind";;
#require "batteries";;
#print_depth 100000000;;
#print_length 100000000;;

open Batteries
open Printf
open Unix

;;

(* process command line paramters *)
assert (Array.length Sys.argv > 5);
let working_directory = Sys.argv.(1) in
let num_of_iterations = int_of_string Sys.argv.(2) in
let new_coq_version = Sys.argv.(3) in
let old_coq_version = Sys.argv.(4) in
let minimal_user_time = float_of_string Sys.argv.(5) in
let sorting_column = Sys.argv.(6) in
let coq_opam_packages = Sys.argv |> Array.to_list |> List.drop 7 in

(* ASSUMPTIONS:

   "working_dir" contains all the files produced by the following command:

      two_points_on_the_same_branch.sh $working_directory $coq_repository $coq_branch[:$new:$old] $num_of_iterations coq_opam_package_1 coq_opam_package_2 ... coq_opam_package_N
-sf
*)

(* Run a given bash command;
   wait until it termines;
   check if its exit status is 0;
   return its whole stdout as a string. *)
let run cmd =
  match run_and_read cmd with
  | WEXITED 0, stdout -> stdout
  | _ -> assert false
in

let nth =
  flip List.nth
in

let proportional_difference_of_integers new_value old_value =
  if old_value = 0
  then Float.nan
  else float_of_int (new_value - old_value) /. float_of_int old_value *. 100.0
in

(* parse the *.time and *.perf files *)

coq_opam_packages
|> List.map
     (fun package_name ->
       package_name,(* compilation_results_for_NEW : (float * int * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".NEW." ^ string_of_int iteration in
              let time_command_output = command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> String.split_on_char ' ' in

              (* NEW_user_time : float *)
              time_command_output |> nth 0 |> float_of_string,

              (* NEW_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* NEW_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* NEW_mem *)
              time_command_output |> nth 1 |> int_of_string,

              (* NEW_faults *)
              time_command_output |> nth 2 |> int_of_string),

       (* compilation_results_for_OLD : (float * int * int * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".OLD." ^ string_of_int iteration in
              let time_command_output = command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> String.split_on_char ' ' in

              (* OLD_user_time : float *)
              time_command_output |> nth 0 |> float_of_string,

              (* OLD_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* OLD_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* OLD_mem *)
              time_command_output |> nth 1 |> int_of_string,

              (* OLD_faults *)
              time_command_output |> nth 2 |> int_of_string))

(* [package_name, [NEW_user_time, NEW_instructions, NEW_cycles, NEW_mem, NEW_faults]      , [OLD_user_time, OLD_instructions, OLD_cycles, OLD_mem, OLD_faults]     ]
 : (string      * (float        * int             * int       * int    * int       ) list * (float        * int             * int       * int    * int       ) list) list *)

(* from the list of measured values, select just the minimal ones *)

|> List.map
     (fun ((package_name : string),
           (new_measurements : (float * int * int * int * int) list),
           (old_measurements : (float * int * int * int * int) list)) ->

       (* : string *)
       package_name,

       (* minimums_of_NEW_measurements : float * int * int * int * int *)
       (
         (* minimal_NEW_user_time : float *)
         new_measurements |> List.map Tuple5.first |> List.reduce min,

         (* minimal_NEW_instructions : int *)
         new_measurements |> List.map Tuple5.second |> List.reduce min,

         (* minimal_NEW_cycles : int *)
         new_measurements |> List.map Tuple5.third |> List.reduce min,

         (* minimal_NEW_mem : int *)
         new_measurements |> List.map Tuple5.fourth |> List.reduce min,

         (* minimal_NEW_faults : int *)
         new_measurements |> List.map Tuple5.fifth |> List.reduce min
       ),

       (* minimums_of_OLD_measurements : float * int * int * int * int *)
       (
         (* minimal_OLD_user_time : float *)
         old_measurements |> List.map Tuple5.first |> List.reduce min,

         (* minimal_OLD_instructions : int *)
         old_measurements |> List.map Tuple5.second |> List.reduce min,

         (* minimal_OLD_cycles : int *)
         old_measurements |> List.map Tuple5.third |> List.reduce min,

         (* minimal_OLD_mem : int *)
         old_measurements |> List.map Tuple5.fourth |> List.reduce min,

         (* minimal_OLD_faults : int *)
         old_measurements |> List.map Tuple5.fifth |> List.reduce min
       )
     )

(* [package_name,
    (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles, minimal_NEW_mem, minimal_NEW_faults),
    (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles, minimal_OLD_mem, minimal_OLD_faults)]
 : (string *
   (float * int * int * int * int) *
   (float * int * int * int * int)) list *)

(* compute the "proportional differences in % of the NEW measurement and the OLD measurement" of all measured values *)
|> List.map
     (fun (package_name,
           (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles, minimal_NEW_mem, minimal_NEW_faults as minimums_of_NEW_measurements),
           (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles, minimal_OLD_mem, minimal_OLD_faults as minimums_of_OLD_measurements)) ->
       package_name,
       minimums_of_NEW_measurements,
       minimums_of_OLD_measurements,
       ((minimal_NEW_user_time -. minimal_OLD_user_time) /. minimal_OLD_user_time *. 100.0,
        proportional_difference_of_integers minimal_NEW_instructions minimal_OLD_instructions,
        proportional_difference_of_integers minimal_NEW_cycles minimal_OLD_cycles,
        proportional_difference_of_integers minimal_NEW_mem minimal_OLD_mem,
        proportional_difference_of_integers minimal_NEW_faults minimal_OLD_faults))

(* [package_name,
    (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles),
    (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles),
    (proportianal_difference_of_user_times,
     proportional_difference_of_instructions,
     proportional_difference_of_cycles,
     proportional_difference_of_mem,
     proportional_difference_of_faults)]

 : (string *
    (float * int   * int   * int   * int) *
    (float * int   * int   * int   * int) *
    (float * float * float * float * float)) list *)

(* sort the table with results *)
|> List.sort
     (match sorting_column with
      | "user_time_pdiff" ->
         (fun measurement1 measurement2 ->
           let get_user_time = Tuple4.fourth %> Tuple5.first in
           compare (get_user_time measurement1) (get_user_time measurement2))
      | "package_name" ->
         (fun measurement1 measurement2 ->
           compare (Tuple4.first measurement1) (Tuple4.first measurement2))
      | _ ->
         assert false
     )

(* Keep only measurements that took at least "minimal_user_time" (in seconds). *)

|> List.filter
     (fun (_, (minimal_NEW_user_time,_,_,_,_), (minimal_OLD_user_time,_,_,_,_), _) ->
        minimal_user_time <= minimal_NEW_user_time && minimal_user_time <= minimal_OLD_user_time)

(* Below we take the measurements and format them to stdout. *)

|> fun measurements ->
     let precision = 2 in

     (* the labels that we will print *)
     let package_name__label = "package_name" in
     let new__label = "NEW" in
     let old__label = "OLD" in
     let proportional_difference__label = "PDIFF" in

     (* the lengths of labels that we will print *)
     let new__label__length = String.length new__label in
     let old__label__length = String.length old__label in
     let proportional_difference__label__length = String.length proportional_difference__label in

     (* widths of individual columns of the table *)
     let package_name__width = max (measurements |> List.map (Tuple4.first %> String.length) |> List.reduce max)
                                   (String.length package_name__label) in
     let new__user_time__width = max ((measurements |> List.map (Tuple4.second %> Tuple5.first)
                                       |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                       new__label__length in
     let new__instructions__width = max (measurements |> List.map (Tuple4.second %> Tuple5.second)
                                         |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                        new__label__length in
     let new__cycles__width = max (measurements |> List.map (Tuple4.second %> Tuple5.third)
                                   |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                  new__label__length in
     let new__mem__width = max (measurements |> List.map (Tuple4.second %> Tuple5.fourth)
                                |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                               new__label__length in
     let new__faults__width = max (measurements |> List.map (Tuple4.second %> Tuple5.fifth)
                                   |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                  new__label__length in
     let old__user_time__width = max ((measurements |> List.map (Tuple4.third %> Tuple5.first)
                                       |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                     old__label__length in
     let old__instructions__width = max (measurements |> List.map (Tuple4.third %> Tuple5.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                          old__label__length in
     let old__cycles__width = max (measurements |> List.map (Tuple4.third %> Tuple5.third)
                                   |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                  old__label__length in
     let old__mem__width = max (measurements |> List.map (Tuple4.third %> Tuple5.fourth)
                                |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                               old__label__length in
     let old__faults__width = max (measurements |> List.map (Tuple4.third %> Tuple5.fifth)
                                |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                               old__label__length in
     let proportional_difference__user_time__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.first %> abs_float) |> List.reduce max
                                                           |> log10 |> floor |> int_of_float |> succ |> max 1) + 2 + precision)
                                                         proportional_difference__label__length in
     let proportional_difference__instructions__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.second %> abs_float) |> List.reduce max
                                                              |> log10 |> floor |> int_of_float |> succ |> max 1) + 2 + precision)
                                                            proportional_difference__label__length in
     let proportional_difference__cycles__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.third %> abs_float) |> List.reduce max
                                                        |> log10 |> floor |> int_of_float |> succ |> max 1) + 2 + precision)
                                                      proportional_difference__label__length in
     let proportional_difference__mem__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.fourth %> abs_float) |> List.reduce max
                                                     |> log10 |> floor |> int_of_float |> succ |> max 1) + 2 + precision)
                                                   proportional_difference__label__length in
     let proportional_difference__faults__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.fifth %> abs_float) |> List.reduce max
                                                        |> log10 |> floor |> int_of_float |> succ |> max 1) + 2 + precision)
                                                      proportional_difference__label__length in

     (* print the table *)

     let rec make_dashes = function
       | 0 -> ""
       | count -> "─" ^ make_dashes (pred count)
     in
     let vertical_separator left_glyph middle_glyph right_glyph = sprintf "%s─%s─%s─%s─%s─%s───%s─%s─%s─%s───%s─%s─%s─%s───%s─%s─%s─%s───%s─%s─%s─%s───%s\n"
       left_glyph
       (make_dashes package_name__width)
       middle_glyph
       (make_dashes new__user_time__width)
       (make_dashes old__user_time__width)
       (make_dashes proportional_difference__user_time__width)
       middle_glyph
       (make_dashes new__cycles__width)
       (make_dashes old__cycles__width)
       (make_dashes proportional_difference__cycles__width)
       middle_glyph
       (make_dashes new__instructions__width)
       (make_dashes old__instructions__width)
       (make_dashes proportional_difference__instructions__width)
       middle_glyph
       (make_dashes new__mem__width)
       (make_dashes old__mem__width)
       (make_dashes proportional_difference__mem__width)
       middle_glyph
       (make_dashes new__faults__width)
       (make_dashes old__faults__width)
       (make_dashes proportional_difference__faults__width)
       right_glyph
     in
     let center_string string width =
       let string_length = String.length string in
       let width = max width string_length in
       let left_hfill = (width - string_length) / 2 in
       let right_hfill = width - left_hfill - string_length in
       String.make left_hfill ' ' ^ string ^ String.make right_hfill ' '
     in
     printf "\n";
     print_string (vertical_separator "┌" "┬" "┐");
     "│" ^ String.make (1 + package_name__width + 1) ' ' ^ "│"
     ^ center_string "user time [s]" (1 +  new__user_time__width + 1 + old__user_time__width + 1 + proportional_difference__user_time__width + 3) ^ "│"
     ^ center_string "CPU cycles" (1 + new__cycles__width    + 1 + old__cycles__width    + 1 + proportional_difference__cycles__width + 3) ^ "│"
     ^ center_string "CPU instructions" (1 + new__instructions__width + 1 + old__instructions__width + 1 + proportional_difference__instructions__width + 3) ^ "│"
     ^ center_string "max resident mem" (1 + new__mem__width + 1 + old__mem__width + 1 + proportional_difference__mem__width + 3) ^ "│"
     ^ center_string "mem faults" (1 + new__faults__width + 1 + old__faults__width + 1 + proportional_difference__faults__width + 3)
     ^ "│\n" |> print_string;
     printf "│%*s │ %*s│ %*s│ %*s│ %*s│ %*s│\n"
       (1 + package_name__width) ""
       (new__user_time__width    + 1 + old__user_time__width    + 1 + proportional_difference__user_time__width + 3) ""
       (new__cycles__width       + 1 + old__cycles__width       + 1 + proportional_difference__cycles__width + 3) ""
       (new__instructions__width + 1 + old__instructions__width + 1 + proportional_difference__instructions__width + 3) ""
       (new__mem__width + 1 + old__mem__width + 1 + proportional_difference__mem__width + 3) ""
       (new__faults__width + 1 + old__faults__width + 1 + proportional_difference__faults__width + 3) "";
     printf "│ %*s │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │\n"
       package_name__width package_name__label
       new__user_time__width new__label
       old__user_time__width old__label
       proportional_difference__user_time__width proportional_difference__label
       new__cycles__width new__label
       old__cycles__width old__label
       proportional_difference__cycles__width proportional_difference__label
       new__instructions__width new__label
       old__instructions__width old__label
       proportional_difference__instructions__width proportional_difference__label
       new__mem__width new__label
       old__mem__width old__label
       proportional_difference__mem__width proportional_difference__label
       new__faults__width new__label
       old__faults__width old__label
       proportional_difference__faults__width proportional_difference__label;
     measurements |> List.iter
         (fun (package_name,
               (new_user_time, new_instructions, new_cycles, new_mem, new_faults),
               (old_user_time, old_instructions, old_cycles, old_mem, old_faults),
               (proportional_difference__user_time, proportional_difference__instructions, proportional_difference__cycles, proportional_difference__mem, proportional_difference__faults)) ->
           print_string (vertical_separator "├" "┼" "┤");
           printf "│ %*s │ %*.*f %*.*f %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │\n"
             package_name__width package_name
             new__user_time__width precision new_user_time
             old__user_time__width precision old_user_time
             proportional_difference__user_time__width precision proportional_difference__user_time
             new__cycles__width new_cycles
             old__cycles__width old_cycles
             proportional_difference__cycles__width precision proportional_difference__cycles
             new__instructions__width new_instructions
             old__instructions__width old_instructions
             proportional_difference__instructions__width precision proportional_difference__instructions         
             new__mem__width new_mem
             old__mem__width old_mem
             proportional_difference__mem__width precision proportional_difference__mem
             new__faults__width new_faults
             old__faults__width old_faults
             proportional_difference__faults__width precision proportional_difference__faults);

print_string (vertical_separator "└" "┴" "┘");
printf "

PDIFF = proportional difference between measurements done for the NEW and the OLD Coq version
      = (NEW_measurement - OLD_measurement) / OLD_measurement * 100%%

NEW = %s
OLD = %s

" new_coq_version old_coq_version;

(* TESTS:

      (* coq-bench/shared/render_results.ml coq-bench/shared/inputs_for_formatting_tests/00-mathcomp-00 10 062afabae15e4d7d96029211effd760d8d730484 37817bb5ac6bb9fa9a4d67a5604a35424f7b343d 0 package_name coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬───────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │                        │     user time [s]     │             CPU cycles              │          CPU instructions           │
      │                        │                       │                                     │                                     │
      │           package_name │    NEW    OLD PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 212.63 213.44 -0.38 % │  706464058475  709196805165 -0.39 % │  711451702236  712651567085 -0.17 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-character │ 319.23 320.73 -0.47 % │ 1082643740546 1088323627566 -0.52 % │ 1139504493386 1141713412512 -0.19 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │     coq-mathcomp-field │ 583.70 590.71 -1.19 % │ 1990210621655 2015346144557 -1.25 % │ 2296309961124 2306640764467 -0.45 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  74.32  74.85 -0.71 % │  238554660588  241040236784 -1.03 % │  246335263268  246673624198 -0.14 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 241.83 242.75 -0.38 % │  806892494982  810003913076 -0.38 % │  861227921524  862801463112 -0.18 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  60.36  60.63 -0.45 % │  178116867145  178136150304 -0.01 % │  171282677609  171356983582 -0.04 % │
      └────────────────────────┴───────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml coq-bench/shared/inputs_for_formatting_tests/00-mathcomp-01 10 062afabae15e4d7d96029211effd760d8d730484 37817bb5ac6bb9fa9a4d67a5604a35424f7b343d 0 package_name coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬───────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │                        │     user time [s]     │             CPU cycles              │          CPU instructions           │
      │                        │                       │                                     │                                     │
      │           package_name │    NEW    OLD PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 212.52 213.17 -0.30 % │  706686348801  710314147087 -0.51 % │  711073932038  712177435195 -0.15 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-character │ 319.97 321.26 -0.40 % │ 1085064343496 1089308833819 -0.39 % │ 1139118960768 1141357953675 -0.20 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │     coq-mathcomp-field │ 583.52 590.59 -1.20 % │ 1992883675381 2015010888610 -1.10 % │ 2295880307828 2306374766977 -0.46 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  74.11  74.73 -0.83 % │  239488168649  240604829599 -0.46 % │  246000684926  246339110521 -0.14 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 241.69 242.31 -0.26 % │  807003389584  809675678158 -0.33 % │  860942356537  862419797782 -0.17 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  60.57  60.07 +0.83 % │  178177984751  178124701650 +0.03 % │  170948226776  171013670382 -0.04 % │
      └────────────────────────┴───────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

   (* marelle1 *)

      (* coq-bench/shared/render_results.ml coq-bench/shared/inputs_for_formatting_tests/02-mathcomp-00 10 8.6 8.5.3 0 user_time_pdiff coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬────────────────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
      │                        │     user time [s]      │              CPU cycles              │           CPU instructions           │
      │                        │                        │                                      │                                      │
      │           package_name │    NEW    OLD  PDIFF   │           NEW           OLD  PDIFF   │           NEW           OLD  PDIFF   │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │     coq-mathcomp-field │ 501.46 794.42 -36.88 % │ 1889816800662 3000863974008 -37.02 % │ 2296192581264 3178649847387 -27.76 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │ coq-mathcomp-character │ 266.32 383.05 -30.47 % │ 1001342364413 1444675626207 -30.69 % │ 1131173310898 1455579092507 -22.29 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 174.10 244.55 -28.81 % │  652926709081  919498603517 -28.99 % │  699634939597  929248877879 -24.71 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 198.02 270.42 -26.77 % │  740915123132 1016390411097 -27.10 % │  850143460082 1069979792475 -20.55 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  43.30  58.36 -25.81 % │  157895171870  215437277471 -26.71 % │  156938887589  211916125534 -25.94 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  57.09  70.39 -18.89 % │  211574889864  261327328228 -19.04 % │  232001619180  274457482721 -15.47 % │
      └────────────────────────┴────────────────────────┴──────────────────────────────────────┴──────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml coq-bench/shared/inputs_for_formatting_tests/03-stdlib 10 8.6 8.5.3 0 package_name stdlib *)

      ┌──────────────┬────────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │              │     user time [s]      │             CPU cycles              │          CPU instructions           │
      │              │                        │                                     │                                     │
      │ package_name │    NEW    OLD  PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├──────────────┼────────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │       stdlib │ 385.71 452.74 -14.81 % │ 1444996061570 1589989599510 -9.12 % │ 1484837046549 1615010725676 -8.06 % │
      └──────────────┴────────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml inputs_for_formatting_tests/04--ppedrot--optim-kernel-array-map--1x 1 2b8ad7e04002ebe9fec5790da924673418f2fa7f 7707396c5010d88c3d0be6ecee816d8da7ed0ee0 0 package_name coq-mathcomp-algebra coq-mathcomp-character coq-mathcomp-field coq-mathcomp-fingroup coq-mathcomp-solvable coq-mathcomp-ssreflect coq-unimath coq-math-classes coq-corn coq-iris coq-hott coq-geocoq coq-flocq coq-coquelicot coq-compcert coq-fiat-parsers coq-fiat-crypto coq-color coq-sf *)

      ┌────────────────────────┬──────────────────────────┬──────────────────────────────────────┬────────────────────────────────────────┐
      │                        │      user time [s]       │              CPU cycles              │            CPU instructions            │
      │                        │                          │                                      │                                        │
      │           package_name │     NEW     OLD  PDIFF   │           NEW           OLD  PDIFF   │            NEW            OLD  PDIFF   │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │              coq-color │  645.06  640.61  +0.69 % │ 1783097251011 1777757343688  +0.30 % │  2279547534756  2290461170093  -0.48 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │           coq-compcert │  827.98  840.65  -1.51 % │ 2300043018951 2331556780029  -1.35 % │  3478065754637  3498203537882  -0.58 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │         coq-coquelicot │   70.54   70.76  -0.31 % │  194866246158  195925462890  -0.54 % │   242880132894   244715879042  -0.75 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │               coq-corn │ 1548.78 1560.34  -0.74 % │ 4301521256384 4335951090334  -0.79 % │  6779678045965  6850323174248  -1.03 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │        coq-fiat-crypto │ 2815.60 2355.87 +19.51 % │ 7832947451714 6544873263777 +19.68 % │ 13008099815235 10858543326881 +19.80 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │       coq-fiat-parsers │  516.60  521.65  -0.97 % │ 1416699342593 1427072057915  -0.73 % │  2001461768544  2024212565132  -1.12 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │              coq-flocq │   52.49   52.06  +0.83 % │  144410326178  144316913004  +0.06 % │   182523752071   183729838540  -0.66 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │             coq-geocoq │ 2258.17 2419.02  -6.65 % │ 6288248705501 6732724529636  -6.60 % │ 10365120731563 11385120187543  -8.96 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │               coq-hott │  232.00  230.20  +0.78 % │  626894322280  621275726154  +0.90 % │  1039478402779  1043069422331  -0.34 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │               coq-iris │  431.38  434.10  -0.63 % │ 1198046292668 1204432879991  -0.53 % │  1714710255629  1723232081400  -0.49 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │       coq-math-classes │  224.83  222.57  +1.02 % │  619746134321  614164801438  +0.91 % │   859606568153   862464567040  -0.33 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │   coq-mathcomp-algebra │  169.50  173.45  -2.28 % │  469794357585  480981983359  -2.33 % │   658773177218   682521608173  -3.48 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │ coq-mathcomp-character │  259.38  270.28  -4.03 % │  721399276682  750376450184  -3.86 % │  1059938738163  1107023978770  -4.25 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │     coq-mathcomp-field │  452.23  487.96  -7.32 % │ 1259154692071 1359158155473  -7.36 % │  2102160359402  2265918499389  -7.23 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │  coq-mathcomp-fingroup │   56.96   58.75  -3.05 % │  157194619141  162084104346  -3.02 % │   216770504609   225572092005  -3.90 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │  coq-mathcomp-solvable │  196.88  202.83  -2.93 % │  546213942885  563019254927  -2.98 % │   799124481406   831011362862  -3.84 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │   43.52   43.96  -1.00 % │  118620060486  119556052957  -0.78 % │   150189090062   151931980911  -1.15 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │                 coq-sf │   44.73   44.81  -0.18 % │  121989713877  122519449380  -0.43 % │   158690248920   159853311446  -0.73 % │
      ├────────────────────────┼──────────────────────────┼──────────────────────────────────────┼────────────────────────────────────────┤
      │            coq-unimath │ 1225.31 1300.68  -5.79 % │ 3398824074880 3605612714343  -5.74 % │  5603181113316  5966571696259  -6.09 % │
      └────────────────────────┴──────────────────────────┴──────────────────────────────────────┴────────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml inputs_for_formatting_tests/05--ppedrot--optim-kernel-array-map--2x/ 2 2b8ad7e04002ebe9fec5790da924673418f2fa7f 7707396c5010d88c3d0be6ecee816d8da7ed0ee0 0 package_name coq-mathcomp-algebra coq-mathcomp-character coq-mathcomp-field coq-mathcomp-fingroup coq-mathcomp-solvable coq-mathcomp-ssreflect coq-unimath coq-math-classes coq-corn coq-iris coq-hott coq-geocoq coq-flocq coq-coquelicot coq-compcert coq-fiat-parsers coq-fiat-crypto coq-color coq-sf *)

      ┌────────────────────────┬─────────────────────────┬─────────────────────────────────────┬───────────────────────────────────────┐
      │                        │      user time [s]      │             CPU cycles              │           CPU instructions            │
      │                        │                         │                                     │                                       │
      │           package_name │     NEW     OLD PDIFF   │           NEW           OLD PDIFF   │            NEW            OLD PDIFF   │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-color │  632.36  632.66 -0.05 % │ 1752403745130 1752253873035 +0.01 % │  2279404804327  2289911626709 -0.46 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │           coq-compcert │  818.24  826.58 -1.01 % │ 2267292209274 2293076056489 -1.12 % │  3477884405878  3498242752193 -0.58 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │         coq-coquelicot │   70.09   70.10 -0.01 % │  193288158782  194036980407 -0.39 % │   242828869250   244756368150 -0.79 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-corn │ 1531.37 1538.66 -0.47 % │ 4253260785911 4269231710019 -0.37 % │  6780119842121  6849057101131 -1.01 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │        coq-fiat-crypto │ 2305.33 2315.82 -0.45 % │ 6410038018359 6439959679069 -0.46 % │ 10816514719325 10864689805515 -0.44 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-fiat-parsers │  511.12  513.78 -0.52 % │ 1402393639585 1409121212222 -0.48 % │  2001361491386  2024058480020 -1.12 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-flocq │   51.68   51.80 -0.23 % │  142738939564  143166801865 -0.30 % │   182462153078   183725483337 -0.69 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │             coq-geocoq │ 2215.65 2394.71 -7.48 % │ 6170994808068 6656242409157 -7.29 % │ 10361347647765 11375764063691 -8.92 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-hott │  230.22  228.16 +0.90 % │  621766384982  616291778379 +0.89 % │  1039452768055  1043443935023 -0.38 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-iris │  425.85  430.56 -1.09 % │ 1183018356474 1192535580136 -0.80 % │  1714537671015  1723851168800 -0.54 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-math-classes │  222.73  220.96 +0.80 % │  612742581504  608562872886 +0.69 % │   859633068673   862349723029 -0.32 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │   coq-mathcomp-algebra │  167.05  171.74 -2.73 % │  463162625899  476465657132 -2.79 % │   658656208840   682405638449 -3.48 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-character │  257.09  266.82 -3.65 % │  714931358748  742477217286 -3.71 % │  1059788621679  1106919778090 -4.26 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │     coq-mathcomp-field │  448.16  482.09 -7.04 % │ 1247302767034 1342347020178 -7.08 % │  2102120885665  2265682765580 -7.22 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-fingroup │   56.05   58.10 -3.53 % │  154738004192  159982326167 -3.28 % │   216940823047   225441075129 -3.77 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-solvable │  193.86  200.76 -3.44 % │  538922552219  556319616458 -3.13 % │   799174021367   831012275426 -3.83 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │   42.99   43.26 -0.62 % │  117760794283  118577057612 -0.69 % │   150366159418   151805550220 -0.95 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │                 coq-sf │   44.31   44.14 +0.39 % │  120895539792  120965434115 -0.06 % │   158704403417   159864692564 -0.73 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │            coq-unimath │ 1210.59 1286.37 -5.89 % │ 3355432194448 3568318753607 -5.97 % │  5603408474428  5966451346906 -6.08 % │
      └────────────────────────┴─────────────────────────┴─────────────────────────────────────┴───────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml inputs_for_formatting_tests/06--ppedrot--optim-kernel-array-map--3x 3 2b8ad7e04002ebe9fec5790da924673418f2fa7f 7707396c5010d88c3d0be6ecee816d8da7ed0ee0 0 package_name coq-mathcomp-algebra coq-mathcomp-character coq-mathcomp-field coq-mathcomp-fingroup coq-mathcomp-solvable coq-mathcomp-ssreflect coq-unimath coq-math-classes coq-corn coq-iris coq-hott coq-geocoq coq-flocq coq-coquelicot coq-compcert coq-fiat-parsers coq-fiat-crypto coq-color coq-sf *)

      ┌────────────────────────┬─────────────────────────┬─────────────────────────────────────┬───────────────────────────────────────┐
      │                        │      user time [s]      │             CPU cycles              │           CPU instructions            │
      │                        │                         │                                     │                                       │
      │           package_name │     NEW     OLD PDIFF   │           NEW           OLD PDIFF   │            NEW            OLD PDIFF   │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-color │  632.84  632.58 +0.04 % │ 1755656108069 1754568792374 +0.06 % │  2279617388030  2290524686550 -0.48 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │           coq-compcert │  820.42  827.43 -0.85 % │ 2275608928694 2300170646037 -1.07 % │  3478363647653  3498641656676 -0.58 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │         coq-coquelicot │   69.96   70.07 -0.16 % │  193450661044  194136982640 -0.35 % │   243118105558   244954363435 -0.75 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-corn │ 1529.06 1536.70 -0.50 % │ 4249075649752 4266436948872 -0.41 % │  6780167729137  6849850448943 -1.02 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │        coq-fiat-crypto │ 2306.59 2311.98 -0.23 % │ 6413686213281 6434015442371 -0.32 % │ 10787861150977 10851330298229 -0.58 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-fiat-parsers │  512.09  514.17 -0.40 % │ 1404818460618 1410889208807 -0.43 % │  2001632645372  2024519937720 -1.13 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-flocq │   51.83   51.88 -0.10 % │  143096612733  143243135805 -0.10 % │   182788386894   183942049134 -0.63 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │             coq-geocoq │ 2208.39 2387.62 -7.51 % │ 6151144891357 6647460881725 -7.47 % │ 10360369825941 11376620935162 -8.93 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-hott │  230.84  228.47 +1.04 % │  622561213384  617297774291 +0.85 % │  1039785809125  1043345765282 -0.34 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-iris │  426.22  429.52 -0.77 % │ 1182317406067 1191327618469 -0.76 % │  1714705054198  1723188227477 -0.49 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-math-classes │  221.42  221.17 +0.11 % │  611464928853  608706769286 +0.45 % │   859872511623   862615347629 -0.32 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │   coq-mathcomp-algebra │  166.51  171.60 -2.97 % │  462637120001  476466651526 -2.90 % │   658898403543   682604491755 -3.47 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-character │  256.81  266.55 -3.65 % │  713971976194  741772173718 -3.75 % │  1060116869072  1107226694164 -4.25 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │     coq-mathcomp-field │  447.49  481.61 -7.08 % │ 1245503165642 1339640568400 -7.03 % │  2102223001791  2266125030207 -7.23 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-fingroup │   56.24   57.94 -2.93 % │  155073015616  159830163838 -2.98 % │   217101130613   225740803718 -3.83 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-solvable │  193.96  199.60 -2.83 % │  538492764404  554879396720 -2.95 % │   799239550216   831199059284 -3.84 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │   43.02   43.11 -0.21 % │  118003063668  118823478229 -0.69 % │   150709078460   152206141117 -0.98 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │                 coq-sf │   44.56   44.31 +0.56 % │  121072471070  121367709344 -0.24 % │   158918527557   160188861450 -0.79 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │            coq-unimath │ 1209.14 1285.05 -5.91 % │ 3353221176309 3564055723614 -5.92 % │  5603642837208  5966129212182 -6.08 % │
      └────────────────────────┴─────────────────────────┴─────────────────────────────────────┴───────────────────────────────────────┘

      (* coq-bench/shared/render_results.ml inputs_for_formatting_tests/07--ppedrot--optim-kernel-array-map--4x 4 2b8ad7e04002ebe9fec5790da924673418f2fa7f 7707396c5010d88c3d0be6ecee816d8da7ed0ee0 0 package_name coq-mathcomp-algebra coq-mathcomp-character coq-mathcomp-field coq-mathcomp-fingroup coq-mathcomp-solvable coq-mathcomp-ssreflect coq-unimath coq-math-classes coq-corn coq-iris coq-hott coq-geocoq coq-flocq coq-coquelicot coq-compcert coq-fiat-parsers coq-fiat-crypto coq-color coq-sf *)

      ┌────────────────────────┬─────────────────────────┬─────────────────────────────────────┬───────────────────────────────────────┐
      │                        │      user time [s]      │             CPU cycles              │           CPU instructions            │
      │                        │                         │                                     │                                       │
      │           package_name │     NEW     OLD PDIFF   │           NEW           OLD PDIFF   │            NEW            OLD PDIFF   │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-color │  643.64  638.47 +0.81 % │ 1784843040029 1772539365191 +0.69 % │  2279786805894  2290506729016 -0.47 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │           coq-compcert │  816.14  829.85 -1.65 % │ 2270771592842 2306853080467 -1.56 % │  3478358624567  3498845656535 -0.59 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │         coq-coquelicot │   69.81   70.39 -0.82 % │  193773970919  194883865570 -0.57 % │   243135870048   245054774850 -0.78 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-corn │ 1532.58 1541.22 -0.56 % │ 4258420440961 4285016085977 -0.62 % │  6779977434194  6849516796832 -1.02 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │        coq-fiat-crypto │ 2310.99 2323.95 -0.56 % │ 6426407548594 6459552048855 -0.51 % │ 10796579408364 10873969323035 -0.71 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-fiat-parsers │  511.01  515.33 -0.84 % │ 1405904491625 1413867604002 -0.56 % │  2001475201356  2024285023690 -1.13 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │              coq-flocq │   52.02   51.98 +0.08 % │  143438417528  143628881167 -0.13 % │   182749322740   183996306551 -0.68 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │             coq-geocoq │ 2224.25 2392.61 -7.04 % │ 6192643290519 6661984282044 -7.05 % │ 10365754363421 11376338670677 -8.88 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-hott │  230.97  229.30 +0.73 % │  624300608859  618728764927 +0.90 % │  1039804003505  1043412711446 -0.35 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │               coq-iris │  427.68  430.11 -0.56 % │ 1187607105068 1196097677292 -0.71 % │  1714915356722  1723692785887 -0.51 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │       coq-math-classes │  222.02  221.23 +0.36 % │  613805260046  610651763712 +0.52 % │   859794370855   862670509079 -0.33 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │   coq-mathcomp-algebra │  167.46  171.85 -2.55 % │  464167050105  477209607400 -2.73 % │   658632921205   682628039419 -3.52 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-character │  257.61  267.45 -3.68 % │  715616329682  743021134232 -3.69 % │  1060083947606  1107206538905 -4.26 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │     coq-mathcomp-field │  447.94  482.30 -7.12 % │ 1245988548336 1341256538957 -7.10 % │  2102314267176  2266062516809 -7.23 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-fingroup │   56.24   58.06 -3.13 % │  155610641887  160156245456 -2.84 % │   216987217213   225748933236 -3.88 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │  coq-mathcomp-solvable │  194.14  200.32 -3.09 % │  538880157866  556433445615 -3.15 % │   799365005594   831284155599 -3.84 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │   43.12   43.30 -0.42 % │  118349716142  118796631474 -0.38 % │   150658778035   152276111576 -1.06 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │                 coq-sf │   44.52   44.66 -0.31 % │  122027190424  122470700197 -0.36 % │   159031253992   160203223263 -0.73 % │
      ├────────────────────────┼─────────────────────────┼─────────────────────────────────────┼───────────────────────────────────────┤
      │            coq-unimath │ 1211.14 1285.76 -5.80 % │ 3357148967878 3567176527620 -5.89 % │  5603610593250  5965815867106 -6.07 % │
      └────────────────────────┴─────────────────────────┴─────────────────────────────────────┴───────────────────────────────────────┘
*)
