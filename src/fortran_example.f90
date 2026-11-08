subroutine example_fortran() bind(c, name="example_fortran")
   write (*, '(A)') '======================================================='
   write (*, '(A)') 'This is an example c++/fortran hybrid project (FORTRAN)'
   write (*, '(A)') '======================================================='
end subroutine example_fortran
