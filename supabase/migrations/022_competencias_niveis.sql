-- Nível de cada competência (executar uma vez no SQL Editor do Supabase)
-- Valores: estudante, empreendedor, empreendedor_plus, empresario
-- Vazio = a competência serve todos os níveis (comportamento anterior).
alter table av_competencies add column if not exists levels text[] not null default '{}';

-- Preencher por código, por exemplo:
-- update av_competencies set levels = array['estudante','empreendedor'] where code in ('COD-01','COD-02');
-- update av_competencies set levels = array['empreendedor_plus','empresario'] where code in ('COD-10','COD-11');
