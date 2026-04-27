-- 项目：olist 电商经营分析项目
-- 文件：15_installment_analysis.sql
-- 作用：提取信用卡分期行为分析数据

with credit_card_order as (
    select
        p.order_id,
        max(p.payment_installments) as payment_installments,
        sum(p.payment_value) as order_payment_value
    from olist_order_payments_dataset p
    join olist_orders_dataset o
        on p.order_id = o.order_id
    where p.payment_type = 'credit_card'
      and o.order_status = 'delivered'
    group by p.order_id
),
installment_base as (
    select
        case
            when payment_installments = 1 then '1. 单期'
            when payment_installments between 2 and 5 then '2. 低分期（2-5期）'
            when payment_installments between 6 and 10 then '3. 中分期（6-10期）'
            when payment_installments > 10 then '4. 高分期（10期以上）'
            else '未知'
        end as installment_group,
        order_payment_value
    from credit_card_order
)
select
    installment_group as '分期档位',
    count(*) as '订单数',
    round(avg(order_payment_value), 2) as '平均订单金额'
from installment_base
group by installment_group
order by installment_group;
