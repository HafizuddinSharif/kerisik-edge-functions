create or replace function public.get_browsable_recipe_save_content(
  p_recipe_id uuid,
  p_include_dev_only boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with recipe as (
    select
      br.id,
      br.imported_content_id,
      br.meal_name,
      br.meal_description,
      br.image_url,
      br.cooking_time,
      br.serving_suggestions
    from public.browsable_recipes br
    where br.id = p_recipe_id
      and (
        br.visibility_status = 'published'::public.visibility_status
        or (
          p_include_dev_only
          and br.visibility_status = 'dev_only'::public.visibility_status
        )
      )
    limit 1
  ),
  imported as (
    select ic.content
    from recipe r
    left join public.imported_content ic on ic.id = r.imported_content_id
  ),
  normalized_ingredients as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', ingredient_group.group_name,
          'sub_ingredients', ingredient_group.sub_ingredients
        )
        order by ingredient_group.sort_order
      ),
      '[]'::jsonb
    ) as ingredients
    from (
      select
        ici.group_name,
        ici.sort_order,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'name', icisi.name,
              'quantity', icisi.quantity,
              'unit', icisi.unit
            )
            order by icisi.sort_order
          ) filter (where icisi.id is not null),
          '[]'::jsonb
        ) as sub_ingredients
      from recipe r
      join public.imported_content_ingredients ici
        on ici.imported_content_id = r.imported_content_id
      left join public.imported_content_sub_ingredients icisi
        on icisi.imported_content_ingredient_id = ici.id
      group by ici.id, ici.group_name, ici.sort_order
    ) ingredient_group
  ),
  fallback_ingredients as (
    select coalesce(content->'ingredients', '[]'::jsonb) as ingredients
    from imported
  )
  select jsonb_build_object(
    'meal_name', r.meal_name,
    'meal_description', coalesce(r.meal_description, i.content->>'meal_description'),
    'ingredients',
      case
        when jsonb_array_length(ni.ingredients) > 0 then ni.ingredients
        else coalesce(fi.ingredients, '[]'::jsonb)
      end,
    'steps', coalesce(i.content->'steps', '[]'::jsonb),
    'cooking_time', coalesce(to_jsonb(r.cooking_time), i.content->'cooking_time'),
    'serving_suggestions', coalesce(to_jsonb(r.serving_suggestions), i.content->'serving_suggestions'),
    'image_url', coalesce(r.image_url, i.content->>'image_url')
  )
  from recipe r
  left join imported i on true
  left join normalized_ingredients ni on true
  left join fallback_ingredients fi on true;
$$;

grant execute on function public.get_browsable_recipe_save_content(uuid, boolean)
  to authenticated, service_role;
