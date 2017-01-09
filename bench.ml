#! /usr/bin/env ocaml

(* TODO:
   - swap the order of "instructions" and "cpu cycles"
     (the order in which we store them into the file)
     (the order in which we represent them in the memory)
*)

(* ASSUMPTIONS:
   - 1-st command line argument (working directory):
     - designates an existing readable directory
     - which contains *.time and *.perf files produced by bench.sh script
   - 2-nd command line argument (number of iterations):
     - is a positive integer
   - the rest of the command line-arguments
     - are names of benchamarked Coq OPAM packages for which bench.sh script generated *.time and *.perf files
 *)

#use "topfind";;
#require "batteries";;
#print_depth 100000000;;
#print_length 100000000;;

open Batteries  (* M-x merlin-use batteries *)
open Printf
open Unix

;;
(* process command line paramters *)
assert (Array.length Sys.argv > 3);
let working_directory = Sys.argv.(1) in
let num_of_iterations = int_of_string Sys.argv.(2) in
let minimal_user_time = float_of_string Sys.argv.(3) in
let coq_opam_packages = Sys.argv |> Array.to_list |> List.drop 4 in

(* Run a given bash command;
   wait until it termines;
   check if its exit status is 0;
   return its whole stdout as a string. *)
let run cmd =
  match run_and_read cmd with
  | WEXITED 0, stdout -> stdout
  | _ -> assert false
in

(* parse the *.time and *.perf files *)

coq_opam_packages
|> List.map
     (fun package_name ->
       package_name,
       
       (* compilation_results_for_HEAD : (float * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".HEAD." ^ string_of_int iteration in

              (* HEAD_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* HEAD_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* HEAD_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string),

       (* compilation_results_for_BASE : (float * int * int) *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".BASE." ^ string_of_int iteration in

              (* BASE_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* BASE_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* BASE_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string))

(* [package_name, [HEAD_user_time, HEAD_instructions, HEAD_cycles]      , [BASE_user_time, BASE_instructions, BASE_cycles]     ]
 :  string      * (float         * int              * int        ) list * (float         * int              * int              ) list) list *)          

(* from the list of measured values, select just the minimal ones *)

|> List.map
     (fun ((package_name : string),
           (head_measurements : (float * int * int) list),
           (base_measurements : (float * int * int) list)) ->

       (* : string *)
       package_name,

       (* minimums_of_HEAD_measurements : float * int * int *)
       (
         (* minimal_HEAD_user_time : float *)
         head_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_HEAD_instructions : int *)
         head_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_HEAD_cycles : int *)
         head_measurements |> List.map Tuple3.third |> List.reduce min
       ),

       (* minimums_of_BASE_measurements : float * int * int *)
       (
         (* minimal_BASE_user_time : float *)
         base_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_BASE_instructions : int *)
         base_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_BASE_cycles : int *)
         base_measurements |> List.map Tuple3.third |> List.reduce min
       )
     )

(* [package_name, (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles) , (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles)]
 : (string      * (float                 * int                      * int                ) * (float                       * int                            * int                      )) list *)

(* compute the "proportional differences in % of the HEAD measurement and the BASE measurement" of all measured values *)
|> List.map
     (fun (package_name,
           (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles as minimums_of_HEAD_measurements),
           (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles as minimums_of_BASE_measurements)) ->
       package_name,
       minimums_of_HEAD_measurements,
       minimums_of_BASE_measurements,
       ((minimal_HEAD_user_time -. minimal_BASE_user_time) /. minimal_BASE_user_time *. 100.0,
        float_of_int (minimal_HEAD_instructions - minimal_BASE_instructions) /. float_of_int minimal_BASE_instructions *. 100.0,
        float_of_int (minimal_HEAD_cycles - minimal_BASE_cycles) /. float_of_int minimal_BASE_cycles *. 100.0))

(* [package_name,
    (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles),
    (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles),
    (proportianal_difference_of_user_times, proportional_difference_of_instructions, proportional_difference_of_cycles)]

 : (string *
    (float * int * int) *
    (float * int * int) *
    (float * float * float)) list *)

(* sort wrt. the proportional difference in user-time *)
|> List.sort
     (fun measurement1 measurement2 ->
        let get_user_time = Tuple4.fourth %> Tuple3.first in
        compare (get_user_time measurement1) (get_user_time measurement2))

(* Keep only measurements that took at least "minimal_user_time" (in seconds). *)

|> List.filter
     (fun (_, (minimal_HEAD_user_time,_,_), (minimal_BASE_user_time,_,_), _) ->
        minimal_user_time <= minimal_HEAD_user_time && minimal_user_time <= minimal_BASE_user_time)

(* Below we take the measurements and format them to stdout. *)

|> fun measurements ->
     let precision = 2 in

     (* the labels that we will print *)
     let package_name__label = "package_name" in
     let head__label = "HEAD" in
     let base__label = "BASE" in
     let proportional_difference__label = "PDIFF" in

     (* the lengths of labels that we will print *)
     let head__label__length = String.length head__label in
     let base__label__length = String.length base__label in
     let proportional_difference__label__length = String.length proportional_difference__label in

     (*
     measurements |> List.map Tuple4.first |> List.iter (printf "DEBUG: package_name = %s\n");
     measurements |> List.map (Tuple4.second %> Tuple3.first) |> List.iter (printf "DEBUG: head__user_time = %f\n");
     measurements |> List.map (Tuple4.second %> Tuple3.second) |> List.iter (printf "DEBUG: head__instructions = %d\n");
     measurements |> List.map (Tuple4.second %> Tuple3.third) |> List.iter (printf "DEBUG: head__cycles = %d\n");
     measurements |> List.map (Tuple4.third %> Tuple3.first) |> List.iter (printf "DEBUG: base__user_time = %f\n");
     measurements |> List.map (Tuple4.third %> Tuple3.second) |> List.iter (printf "DEBUG: base__instructions = %d\n");
     measurements |> List.map (Tuple4.third %> Tuple3.third) |> List.iter (printf "DEBUG: base__cycles = %d\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.first) |> List.iter (printf "DEBUG: proportional_difference__user_time = %f\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.second) |> List.iter (printf "DEBUG: proportional_difference__instructions = %f\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.third) |> List.iter (printf "DEBUG: proportional_difference__cycles = %f\n");
     *)

     (* widths of individual columns of the table *)
     let package_name__width = max (measurements |> List.map (Tuple4.first %> String.length) |> List.reduce max)
                                   (String.length package_name__label) in
     let head__user_time__width = max ((measurements |> List.map (Tuple4.second %> Tuple3.first)
                                        |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                      head__label__length in
     let head__instructions__width = max (measurements |> List.map (Tuple4.second %> Tuple3.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                         head__label__length in
     let head__cycles__width = max (measurements |> List.map (Tuple4.second %> Tuple3.third)
                                    |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                   head__label__length in
     let base__user_time__width = max ((measurements |> List.map (Tuple4.third %> Tuple3.first)
                                        |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                      base__label__length in
     let base__instructions__width = max (measurements |> List.map (Tuple4.third %> Tuple3.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                         base__label__length in
     let base__cycles__width = max (measurements |> List.map (Tuple4.third %> Tuple3.third)
                                    |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                   base__label__length
     in
     let proportional_difference__user_time__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.first %> abs_float) |> List.reduce max
                                                           |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                         proportional_difference__label__length in
     let proportional_difference__instructions__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.second %> abs_float) |> List.reduce max
                                                              |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                            proportional_difference__label__length in
     let proportional_difference__cycles__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.third %> abs_float) |> List.reduce max
                                                        |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                      proportional_difference__label__length in

     (* print the table *)

     let rec make_dashes = function
       | 0 -> ""
       | count -> "─" ^ make_dashes (pred count)
     in
     let vertical_separator left_glyph middle_glyph right_glyph = sprintf "%s─%s─%s─%s─%s─%s───%s─%s─%s─%s───%s─%s─%s─%s───%s\n"
       left_glyph
       (make_dashes package_name__width)
       middle_glyph
       (make_dashes head__user_time__width)
       (make_dashes base__user_time__width)
       (make_dashes proportional_difference__user_time__width)
       middle_glyph
       (make_dashes head__cycles__width)
       (make_dashes base__cycles__width)
       (make_dashes proportional_difference__cycles__width)
       middle_glyph
       (make_dashes head__instructions__width)
       (make_dashes base__instructions__width)
       (make_dashes proportional_difference__instructions__width)
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
     ^ center_string "user time" (1 +  head__user_time__width + 1 + base__user_time__width + 1 + proportional_difference__user_time__width + 3) ^ "│"
     ^ center_string "CPU cycles" (1 + head__cycles__width    + 1 + base__cycles__width    + 1 + proportional_difference__cycles__width + 3) ^ "│"
     ^ center_string "CPU instructions" (1 + head__instructions__width + 1 + base__instructions__width + 1 + proportional_difference__instructions__width + 3)
     ^ "│\n" |> print_string;
     printf "│%*s │ %*s│ %*s│ %*s│\n"
       (1 + package_name__width) ""
       (head__user_time__width      + 1 + base__user_time__width    + 1 + proportional_difference__user_time__width + 3) ""
       (head__cycles__width       + 1 + base__cycles__width       + 1 + proportional_difference__cycles__width + 3) ""
       (head__instructions__width + 1 + base__instructions__width + 1 + proportional_difference__instructions__width + 3) "";
     printf "│ %*s │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │\n"
       package_name__width package_name__label
       head__user_time__width head__label
       base__user_time__width base__label
       proportional_difference__user_time__width proportional_difference__label
       head__cycles__width head__label
       base__cycles__width base__label
       proportional_difference__cycles__width proportional_difference__label
       head__instructions__width head__label
       base__instructions__width base__label
       proportional_difference__instructions__width proportional_difference__label;
     measurements |> List.iter
         (fun (package_name,
               (head_user_time, head_instructions, head_cycles),
               (base_user_time, base_instructions, base_cycles),
               (proportional_difference__user_time, proportional_difference__instructions, proportional_difference__cycles)) ->
           print_string (vertical_separator "├" "┼" "┤");
           printf "│ %*s │ %*.*f %*.*f %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │\n"
             package_name__width package_name
             head__user_time__width precision head_user_time
             base__user_time__width precision base_user_time
             proportional_difference__user_time__width precision proportional_difference__user_time
             head__cycles__width head_cycles
             base__cycles__width base_cycles
             proportional_difference__cycles__width precision proportional_difference__cycles
             head__instructions__width head_instructions
             base__instructions__width base_instructions
             proportional_difference__instructions__width precision proportional_difference__instructions);

print_string (vertical_separator "└" "┴" "┘");
printf "

\"user time\" is in seconds

 HEAD ... measurements at the HEAD of your branch
 BASE ... measurements at the latest common commit of your branch and the official Coq branch (so called \"merge-base\" point)
PDIFF ... proportional difference of the HEAD and BASE measurements
          (HEAD_measurement - BASE_measurement) / BASE_measurement * 100%%

";

(* TESTS:

   ./bench.ml inputs_for_formatting_tests/a 3 0 coq-aac-tactics

        ┌─────────────────┬─────────────────────┬─────────────────────────────────┬─────────────────────────────────┐
        │                 │      user time      │           CPU cycles            │        CPU instructions         │
        │                 │                     │                                 │                                 │
        │    package_name │  HEAD  BASE PDIFF   │        HEAD        BASE PDIFF   │        HEAD        BASE PDIFF   │
        ├─────────────────┼─────────────────────┼─────────────────────────────────┼─────────────────────────────────┤
        │ coq-aac-tactics │ 12.18 11.40 +6.84 % │ 43313124698 41947595925 +3.26 % │ 47396322602 44780155894 +5.84 % │
        └─────────────────┴─────────────────────┴─────────────────────────────────┴─────────────────────────────────┘


   ./bench.ml inputs_for_formatting_tests/b 1 0 coq-abp coq-zf

        ┌──────────────┬─────────────────────┬──────────────────────────────────┬─────────────────────────────────┐
        │              │      user time      │            CPU cycles            │        CPU instructions         │
        │              │                     │                                  │                                 │
        │ package_name │  HEAD BASE  PDIFF   │        HEAD        BASE  PDIFF   │        HEAD        BASE PDIFF   │
        ├──────────────┼─────────────────────┼──────────────────────────────────┼─────────────────────────────────┤
        │      coq-abp │  7.67 7.80  -1.67 % │ 28725701399 29219013046  -1.69 % │ 32930749122 32935004729 -0.01 % │
        ├──────────────┼─────────────────────┼──────────────────────────────────┼─────────────────────────────────┤
        │       coq-zf │ 10.32 7.68 +34.38 % │ 38467675997 27497499103 +39.90 % │ 32657861506 32659994172 -0.01 % │
        └──────────────┴─────────────────────┴──────────────────────────────────┴─────────────────────────────────┘


   ./bench.ml inputs_for_formatting_tests/c 3 0 coq-mathcomp-algebra coq-mathcomp-character coq-mathcomp-field coq-mathcomp-fingroup coq-mathcomp-solvable coq-mathcomp-ssreflect

        ┌────────────────────────┬──────────────────────────┬───────────────────────────────────────┬───────────────────────────────────────┐
        │                        │        user time         │              CPU cycles               │           CPU instructions            │
        │                        │                          │                                       │                                       │
        │           package_name │    HEAD   BASE   PDIFF   │          HEAD          BASE   PDIFF   │          HEAD          BASE   PDIFF   │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │  coq-mathcomp-fingroup │   57.57  57.39   +0.31 % │  212196525523  211700800619   +0.23 % │  230742383528  231051582985   -0.13 % │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │ coq-mathcomp-ssreflect │   44.16  43.76   +0.91 % │  157468537172  157129657017   +0.22 % │  156209219792  155462303481   +0.48 % │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │  coq-mathcomp-solvable │  239.79 199.12  +20.42 % │  895688256644  742909321481  +20.56 % │ 1045508031859  847593471137  +23.35 % │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │   coq-mathcomp-algebra │  378.67 175.35 +115.95 % │ 1410735202916  653030070797 +116.03 % │ 1469054879541  697258305890 +110.69 % │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │     coq-mathcomp-field │ 1790.52 498.74 +259.01 % │ 6748094598910 1876624387627 +259.59 % │ 8682577070704 2292383630876 +278.76 % │
        ├────────────────────────┼──────────────────────────┼───────────────────────────────────────┼───────────────────────────────────────┤
        │ coq-mathcomp-character │  964.52 266.90 +261.38 % │ 3638431192496 1000837103539 +263.54 % │ 4254625106615 1126775092470 +277.59 % │
        └────────────────────────┴──────────────────────────┴───────────────────────────────────────┴───────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/d 10 0 coq-persistent-union-find

        ┌───────────────────────────┬──────────────────────┬───────────────────────────────────┬────────────────────────────────────┐
        │                           │      user time       │            CPU cycles             │          CPU instructions          │
        │                           │                      │                                   │                                    │
        │              package_name │  HEAD  BASE  PDIFF   │         HEAD        BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├───────────────────────────┼──────────────────────┼───────────────────────────────────┼────────────────────────────────────┤
        │ coq-persistent-union-find │ 52.00 30.39 +71.11 % │ 168903203726 98378322597 +71.69 % │ 177308860658 112340449808 +57.83 % │
        └───────────────────────────┴──────────────────────┴───────────────────────────────────┴────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/e 10 0 coq-persistent-union-find

        ┌───────────────────────────┬──────────────────────┬───────────────────────────────────┬────────────────────────────────────┐
        │                           │      user time       │            CPU cycles             │          CPU instructions          │
        │                           │                      │                                   │                                    │
        │              package_name │  HEAD  BASE  PDIFF   │         HEAD        BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├───────────────────────────┼──────────────────────┼───────────────────────────────────┼────────────────────────────────────┤
        │ coq-persistent-union-find │ 51.86 30.40 +70.59 % │ 168590915216 98387933632 +71.35 % │ 177249568577 112342334134 +57.78 % │
        └───────────────────────────┴──────────────────────┴───────────────────────────────────┴────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/f 10 0 coq-gc

        ┌──────────────┬────────────────────────┬────────────────────────────────────┬────────────────────────────────────┐
        │              │       user time        │             CPU cycles             │          CPU instructions          │
        │              │                        │                                    │                                    │
        │ package_name │   HEAD   BASE  PDIFF   │         HEAD         BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├──────────────┼────────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │       coq-gc │ 152.22 118.68 +28.26 % │ 493890013225 383210349553 +28.88 % │ 454226788229 363922855469 +24.81 % │
        └──────────────┴────────────────────────┴────────────────────────────────────┴────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/g 10 0 coq-gc

        ┌──────────────┬────────────────────────┬────────────────────────────────────┬────────────────────────────────────┐
        │              │       user time        │             CPU cycles             │          CPU instructions          │
        │              │                        │                                    │                                    │
        │ package_name │   HEAD   BASE  PDIFF   │         HEAD         BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├──────────────┼────────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │       coq-gc │ 152.65 118.46 +28.86 % │ 494267863364 384050516870 +28.70 % │ 454178074635 363803278377 +24.84 % │
        └──────────────┴────────────────────────┴────────────────────────────────────┴────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/h 10 0 coq-pi-calc coq-otway-rees coq-lazy-pcf

        ┌────────────────┬──────────────────────┬────────────────────────────────────┬────────────────────────────────────┐
        │                │      user time       │             CPU cycles             │          CPU instructions          │
        │                │                      │                                    │                                    │
        │   package_name │  HEAD  BASE  PDIFF   │         HEAD         BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │   coq-lazy-pcf │  6.86  6.96  -1.44 % │  20626707131  20644923463  -0.09 % │  27012382562  27109159492  -0.36 % │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │ coq-otway-rees │  7.96  8.02  -0.75 % │  23404622634  23516567732  -0.48 % │  30820246815  30970294528  -0.48 % │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │    coq-pi-calc │ 70.04 56.52 +23.92 % │ 227041402678 183143495642 +23.97 % │ 258190739644 210406262998 +22.71 % │
        └────────────────┴──────────────────────┴────────────────────────────────────┴────────────────────────────────────┘


    (* notebook: ThinkPad X230 *)
    ./bench.ml inputs_for_formatting_tests/i 10 0 coq-pi-calc coq-otway-rees coq-lazy-pcf

        ┌────────────────┬──────────────────────┬────────────────────────────────────┬────────────────────────────────────┐
        │                │      user time       │             CPU cycles             │          CPU instructions          │
        │                │                      │                                    │                                    │
        │   package_name │  HEAD  BASE  PDIFF   │         HEAD         BASE  PDIFF   │         HEAD         BASE  PDIFF   │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │   coq-lazy-pcf │  6.94  6.98  -0.57 % │  20617469650  20691515078  -0.36 % │  27017623379  27114705474  -0.36 % │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │ coq-otway-rees │  8.02  7.86  +2.04 % │  23468126863  23557180748  -0.38 % │  30828060320  30972789098  -0.47 % │
        ├────────────────┼──────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
        │    coq-pi-calc │ 70.20 56.65 +23.92 % │ 227639688878 183643929078 +23.96 % │ 258240087091 211361180925 +22.18 % │
        └────────────────┴──────────────────────┴────────────────────────────────────┴────────────────────────────────────┘
*)
