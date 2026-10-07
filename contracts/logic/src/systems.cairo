/// `ActionLibrary`: the adventurer's combat action (Attack, Skill, Item) as a library class
/// (CBT-05b's action phase; D-233).
pub mod action;
pub mod segment;
/// `AiLibrary`: the goblins' acts, step 2 of a tick, as a library class called once a tick
/// (ENG-07 Open question 1, candidate C).
pub mod ai;
/// `ExecutorLibrary`: the executor as its own library class, one call a carrier (CBT-05a, the
/// own-class route measured for the project manager).
pub mod executor;
/// `FlattenLibrary`: the snapshot's flattening as a library class (CBT-02e, D-168).
pub mod flatten;
/// `HostsLibrary`: a zone's quota hosts drawn at `create`, as a library class (ENG-05, D-210).
pub mod hosts;
/// `RevealLibrary`: the chunk reveal as a library class (ENG-05).
pub mod reveal;
/// `TickLibrary`: the world tick's pipeline as a library class (CBT-02), and the action phase
/// before it (CBT-05b, D-222).
pub mod tick;
/// `TrapLibrary`: a trap's trigger as a library class (CBT-05b, D-222).
pub mod trap;
