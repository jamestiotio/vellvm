define i32 @main(i32 %argc, i8** %arcv) {
  %1 = sub nuw i32 0, 1
  ret i32 %1
}

; ASSERT POISON: call i32 @main(i32 1, i8** null)
