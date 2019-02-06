# Welcome to Coq Bench!

coq-bench is a set of scripts that allow users to track performance
changes between two different versions of Coq.

The scripts can be run on INRIA's Jenkins instance or in your own machine.

## Submitting a benchmark to INRIA's Jenkins infrastructure:

See (Jenkins Instructions)[https://github.com/coq/coq/wiki/Jenkins-(automated-benchmarking)]

Results can be seen at https://ci.inria.fr/coq/job/benchmark-part-of-the-branch/

## Contributing

Maintainer of coq-bench is Emilio Jesús Gallego Arias; see the
[contributing](./CONTRIBUTING.md) file information about contributing
to this software.

## Adding your package for testing.

- Add your package to the `coq-extra-dev` OPAM repository
  https://github.com/coq/opam-coq-archive , for that you'll need to
  submit a pull request.

- Go to the web UI
  https://ci.inria.fr/coq/view/benchmarking/job/benchmark-part-of-the-branch/configure
  and add the package to the default list. You will need admin
  privileges on the CI instance in order to do this.

## Running a bench locally:

Soon, see Travis file to see how the setup works.
