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
(*assert (Array.length Sys.argv > 3);
let working_directory = Sys.argv.(1) in
let num_of_iterations = int_of_string Sys.argv.(2) in
let coq_opam_packages = Sys.argv |> Array.to_list |> List.drop 3 in*)
let working_directory = "/tmp/b" in
let num_of_iterations = 1 in
let coq_opam_packages = ["coq-aac-tactics"] in

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
       
       (* compilation_results_of_HEAD : (float * int * int) list *)
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

       (* compilation_results_of_MERGE_BASE : (float * int * int) *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".MERGE_BASE." ^ string_of_int iteration in

              (* MERGE_BASE_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* MERGE_BASE_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* MERGE_BASE_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string))

(* [package_name, [HEAD_user_time, HEAD_instructions, HEAD_cycles]      , [MERGE_BASE_user_time, MERGE_BASE_instructions, MERGE_BASE_cycles]     ]
 :  string      * (float         * int              * int        ) list * (float               * int                    * int              ) list) list *)          

(* from the list of measured values, select just the minimal ones *)

|> List.map
     (fun ((package_name : string),
           (head_measurements : (float * int * int) list),
           (merge_base_measurements : (float * int * int) list)) ->

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

       (* minimums_of_MERGE_BASE_measurements : float * int * int *)
       (
         (* minimal_MERGE_BASE_user_time : float *)
         merge_base_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_MERGE_BASE_instructions : int *)
         merge_base_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_MERGE_BASE_cycles : int *)
         merge_base_measurements |> List.map Tuple3.third |> List.reduce min
       )
     )

(* [package_name, (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles) , (minimal_MERGE_BASE_user_time, minimal_MERGE_BASE_instructions, minimal_MERGE_BASE_cycles)]
 : (string      * (float                 * int                      * int                ) * (float                       * int                            * int                      )) list *)

(* compute the "proportional differences in % of the HEAD measurement and the MERGE_BASE measurement" of all measured values *)
|> List.map
     (fun (package_name,
           (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles as minimums_of_HEAD_measurements),
           (minimal_MERGE_BASE_user_time, minimal_MERGE_BASE_instructions, minimal_MERGE_BASE_cycles as minimums_of_MERGE_BASE_measurements)) ->
       package_name,
       minimums_of_HEAD_measurements,
       minimums_of_MERGE_BASE_measurements,
       ((minimal_HEAD_user_time -. minimal_MERGE_BASE_user_time) /. minimal_MERGE_BASE_user_time *. 100.0,
        float_of_int (minimal_HEAD_instructions - minimal_MERGE_BASE_instructions) /. float_of_int minimal_MERGE_BASE_instructions *. 100.0,
        float_of_int (minimal_HEAD_cycles - minimal_MERGE_BASE_cycles) /. float_of_int minimal_MERGE_BASE_cycles *. 100.0))

(* [package_name,
    (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles),
    (minimal_MERGE_BASE_user_time, minimal_MERGE_BASE_instructions, minimal_MERGE_BASE_cycles),
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

|> tap (fun measurements -> ())

|> fun measurements ->
     let precision = 2 in
     let package_name__width = measurements |> List.map (Tuple4.first %> String.length) |> List.reduce max in
     let head__user_time__width = (measurements |> List.map (Tuple4.second %> Tuple3.first) |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision in
     let head__instructions__width = measurements |> List.map (Tuple4.second %> Tuple3.second) |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float in
     let head__cycles__width = measurements |> List.map (Tuple4.second %> Tuple3.third) |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float in
     let merge_base__user_time__width = (measurements |> List.map (Tuple4.third %> Tuple3.first) |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision in
     let merge_base__instructions__width = measurements |> List.map (Tuple4.third %> Tuple3.second) |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float in
     let merge_base__cycles__width = measurements |> List.map (Tuple4.third %> Tuple3.third) |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float in
     let proportional_difference__user_time__width = (measurements |> List.map (Tuple4.fourth %> Tuple3.first) |> List.reduce max |> log10 |> ceil |> int_of_float) + 2 + precision in
     let proportional_difference__instructions__width = (measurements |> List.map (Tuple4.fourth %> Tuple3.second) |> List.reduce max |> log10 |> ceil |> int_of_float) + 2 + precision in
     let proportional_difference__cycles__width = (measurements |> List.map (Tuple4.fourth %> Tuple3.third) |> List.reduce max |> log10 |> ceil |> int_of_float) + 2 + precision in

     measurements |> List.map (Tuple4.fourth %> Tuple3.first) |> List.iter (printf "DEBUG: 0.0: %f\n"); printf "\n";
     measurements |> List.map (Tuple4.fourth %> Tuple3.second) |> List.iter (printf "DEBUG: 0.1: %f\n"); printf "\n";
     measurements |> List.map (Tuple4.fourth %> Tuple3.third) |> List.iter (printf "DEBUG: 0.2: %f\n"); printf "\n";

     printf "DEBUG 0: proportional_difference__user_time__width = %d\n" proportional_difference__user_time__width;
     printf "DEBUG 1: proportional_difference__instructions__width = %d\n" proportional_difference__instructions__width;
     printf "DEBUG 2: proportional_difference__cycles__width = %d\n" proportional_difference__cycles__width;
     measurements |> List.map (Tuple4.fourth %> Tuple3.third) |> List.iter (printf "DEBUG 10: %+f\n");
     let make_dashes count = String.make count '-' in
     let vertical_separator = sprintf "+-%s-+-%s-%s--%s--+-%s-%s-%s---+-%s-%s--%s--+\n"
       (make_dashes package_name__width)
       (make_dashes head__user_time__width)
       (make_dashes merge_base__user_time__width)
       (make_dashes proportional_difference__user_time__width)
       (make_dashes head__cycles__width)
       (make_dashes merge_base__cycles__width)
       (make_dashes proportional_difference__cycles__width)
       (make_dashes head__instructions__width)
       (make_dashes merge_base__instructions__width)
       (make_dashes proportional_difference__instructions__width)
     in
     print_string vertical_separator;
     measurements |> List.iter
         (fun (package_name,
               (head_user_time, head_instructions, head_cycles),
               (merge_base_user_time, merge_base_instructions, merge_base_cycles),
               (proportional_difference__user_time, proportional_difference__instructions, proportional_difference__cycles)) ->
           printf "| %*s | %*.*f %*.*f %+*.*f %% | %*d %*d %+*.*f %% | %*d %*d %+*.*f %% |\n"
             package_name__width package_name
             head__user_time__width precision head_user_time
             merge_base__user_time__width precision merge_base_user_time
             proportional_difference__user_time__width precision proportional_difference__user_time
             head__cycles__width head_cycles
             merge_base__cycles__width merge_base_cycles
             proportional_difference__cycles__width precision proportional_difference__cycles
             head__instructions__width head_instructions
             merge_base__instructions__width merge_base_instructions
             proportional_difference__instructions__width precision proportional_difference__instructions;
           print_string vertical_separator)
