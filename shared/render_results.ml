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

let count_number_of_digits_before_decimal_point =
  log10 %> floor %> int_of_float %> succ %> max 1
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
                                       |> List.reduce max |> count_number_of_digits_before_decimal_point) + 1 + precision)
                                       new__label__length in
     let new__instructions__width = max (measurements |> List.map (Tuple4.second %> Tuple5.second)
                                         |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                                        new__label__length in
     let new__cycles__width = max (measurements |> List.map (Tuple4.second %> Tuple5.third)
                                   |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                                  new__label__length in
     let new__mem__width = max (measurements |> List.map (Tuple4.second %> Tuple5.fourth)
                                |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                               new__label__length in
     let new__faults__width = max (measurements |> List.map (Tuple4.second %> Tuple5.fifth)
                                   |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                                  new__label__length in
     let old__user_time__width = max ((measurements |> List.map (Tuple4.third %> Tuple5.first)
                                       |> List.reduce max |> count_number_of_digits_before_decimal_point) + 1 + precision)
                                     old__label__length in
     let old__instructions__width = max (measurements |> List.map (Tuple4.third %> Tuple5.second)
                                          |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                                          old__label__length in
     let old__cycles__width = max (measurements |> List.map (Tuple4.third %> Tuple5.third)
                                   |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                                  old__label__length in
     let old__mem__width = max (measurements |> List.map (Tuple4.third %> Tuple5.fourth)
                                |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                               old__label__length in
     let old__faults__width = max (measurements |> List.map (Tuple4.third %> Tuple5.fifth)
                                |> List.reduce max |> float_of_int |> count_number_of_digits_before_decimal_point)
                               old__label__length in
     let proportional_difference__user_time__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.first %> abs_float) |> List.reduce max
                                                           |> count_number_of_digits_before_decimal_point) + 2 + precision)
                                                         proportional_difference__label__length in
     let proportional_difference__instructions__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.second %> abs_float) |> List.reduce max
                                                              |> count_number_of_digits_before_decimal_point) + 2 + precision)
                                                            proportional_difference__label__length in
     let proportional_difference__cycles__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.third %> abs_float) |> List.reduce max
                                                        |> count_number_of_digits_before_decimal_point) + 2 + precision)
                                                      proportional_difference__label__length in
     let proportional_difference__mem__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.fourth %> abs_float) |> List.reduce max
                                                     |> count_number_of_digits_before_decimal_point) + 2 + precision)
                                                   proportional_difference__label__length in
     let proportional_difference__faults__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple5.fifth %> abs_float) |> List.reduce max
                                                        |> count_number_of_digits_before_decimal_point) + 2 + precision)
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
     ^ center_string "max resident mem [KB]" (1 + new__mem__width + 1 + old__mem__width + 1 + proportional_difference__mem__width + 3) ^ "│"
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

(* ejgallego: disable this as it is very verbose and brings up little info in the log. *)
if false then begin
printf "

PDIFF = proportional difference between measurements done for the NEW and the OLD Coq version
      = (NEW_measurement - OLD_measurement) / OLD_measurement * 100%%

NEW = %s
OLD = %s

Columns:

  1. user time [s]

     Total number of CPU-seconds that the process used directly (in user mode), in seconds.
     (In other words, \"%%U\" quantity provided by the \"/usr/bin/time\" command.)

  2. CPU cycles

     Total number of CPU-cycles that the process used directly (in user mode).
     (In other words, \"cycles:u\" quantity provided by the \"/usr/bin/perf\" command.)

  3. CPU instructions

     Total number of CPU-instructions that the process used directly (in user mode).
     (In other words, \"instructions:u\" quantity provided by the \"/usr/bin/perf\" command.)

  4. max resident mem [KB]

     Maximum resident set size of the process during its lifetime, in Kilobytes.
     (In other words, \"%%M\" quantity provided by the \"/usr/bin/time\" command.)

  5. mem faults

     Number of major, or I/O-requiring, page faults that occurred while the process was running.
     These are faults where the page has actually migrated out of primary memory.
     (In other words, \"%%F\" quantity provided by the \"/usr/bin/time\" command.)

" new_coq_version old_coq_version;
end
