drop policy "Users can view their own imported content" on "public"."imported_content";

create policy "Users can view all imported content"
on "public"."imported_content"
as permissive
for select
to authenticated
using (true);



