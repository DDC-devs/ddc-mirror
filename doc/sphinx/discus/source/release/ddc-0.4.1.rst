
The Disciplined Disciple Compiler 0.4.1 (2014/03/09)
====================================================

DDC is a research compiler used to investigate program transformation in the
presence of computational effects. This is a development release. There is
enough implemented to experiment with the language, but not enough to solve
actual problems...        (unless you're looking for a compiler to hack on).

DDC compiles several related languages.

 * Disciple Tetra (.dst)

   An implicitly typed strict functional language with region and effect
   typing. Uses effect reification (`box`) and reflection (`run`) casts to
   compose computations with differing effects. Effectful computations are
   classified by the `S e a` type, for some effect `e` and return type `a`.
   Although type inference is supported, one can also write explicit type
   abstractions and applications when needed. Higher ranked types are supported
   with annotations.

 * Disciple Core Tetra (.dct)

   The desugared version of Disciple Tetra. All function application is in
   prefix form. This language also supports type inference, though the
   inferencer does not insert additional type quantifiers.

 * Disciple Core Lite (.dcl)

   Uses a Lucassen and Gifford style polymorphic effect system rather than
   one using reification and reflection. Effectful computations are classified
   by a function type with a latent effect annotation. This language also
   includes an experimental closure typing system.

 * Disciple Core Flow (.dcf)

   Application specific language with built-in support for Series expressions
   and Data Flow Fusion. This language and its associated transforms is used by
   the repa-plugin available on Hackage.

 * Disciple Core Salt (.dcs)

   A fragment of Disciple Core that can be easily mapped onto C or LLVM code.
   The Salt language is first-order and does not support partial application.
   DDC transforms the higher level languages onto this one during code
   generation, though we can also write programs in it directly.

 * Disciple Core Eval (.dce) (deprecated)

   Similar to Disciple Core Lite, except without unboxed primitive types.
   This language is accepted by the interpreter. In future work we will
   interpret Disciple Core Tetra directly and remove the separate Core Eval
   language.

All core languages share the same abstract syntax tree (AST), type inferencer,
and are amenable to many of the same program transformations. They differ only
in the set of allowable language features, and which primitive types and
operators are included.


Main changes since 0.3.2
------------------------

 * Added a bi-directional type inferencer based on Joshua Dunﬁeld and
   Neelakantan Krishnaswami's recent ICFP paper.

 * Added a region extension language construct, and coeffect system.

 * Civilized error messages for unsupported or incomplete features.

 * Added the Disciple Tetra language which includes infix operators and
   desugars into Disciple Core Tetra.

 * Compilation of Tetra and Core Tetra programs to C and LLVM.

 * Early support for rate inference in Core Flow.

 * Flow fusion now generates vector primops for maps and folds.

 * Support for user-defined algebraic data types.

 * Most type error messages now give source locations.

 * Building on Windows platforms.

 * Better support for foreign imported types and values.

 * Changed to Git for version control.


What works in this release
--------------------------

 * Parsing and type inference for the Tetra, Lite, Flow, Salt and Eval
   languages.

 * Compilation via C and LLVM for first-order Tetra, Lite and Salt programs.

 * Interpreter for the full Eval language.

 * Data Flow Fusion for the Flow language.

 * Program transformations: Anonymize (remove names), Beta (substitute),
   Bubble (move type-casts), Elaborate (add witnesses), Flatten (eliminate
   nested bindings), Forward (let-floating), Namify (add names), Prune
   (dead-code elimination), Snip (eliminate nested applications), Rewrite
   rules, cross-module inlining.


What doesn't
------------

 * No code generation for higher order functions.
   The type inferencer and program transformations support it, but we don't
   yet have a lambda lifter, or the runtime support.

 * No storage management.
   There is a fixed 64k heap and when you've allocated that much space the
   runtime just calls abort().

 * No multi-module compilation driver.
   DDC isn't restricted to whole-program compilation, but the --make driver
   doesn't handle multiple modules. You'd need to do the linking yourself.


Previous Releases
-----------------

 * 2013/07 DDC 0.3.2: Added Tetra and Flow language fragments.
 * 2012/12 DDC 0.3.1: Added Lite fragment, compilation to C and LLVM.
 * 2012/02 DDC 0.2.0: Project reboot. New core language, working interpreter.
 * 2008/07 DDC 0.1.1: Alpha compiler, constructor classes, more examples.
 * 2008/03 DDC 0.1.0: Alpha compiler, used dependently kinded core language.


Immediate Plans
---------------

 1. Finish code generation for higher order functions and partial application.

 2. Automatically insert `run` and `box` casts during type inference.


How you can help
----------------

 1. Work through the tutorial on the web-site and send any comments to the
    mailing list.

 2. Say hello on the mailing list and we can help you get started on any of
    the main missing features. These are all interesting projects.

 3. Tell your friends.


People
------

The following people contributed to DDC since the last major release:

 * Kyle van Berendonck    -- Building on windows, bug fixes.
 * Erik de Castro Lopo    -- Build system tweaks.
 * Ben Lippmeier          -- Type inferencer, code generation.
 * Amos Robinson          -- Rate inference for flow fusion.

