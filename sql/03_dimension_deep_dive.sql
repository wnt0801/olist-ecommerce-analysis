use xiangmu;

-- =============================================
-- 7. 支付结构分析
-- 看平台收款结构
-- =============================================

select
    p.payment_type,
    count(distinct p.order_id) as '订单量',
    round(sum(p.payment_value), 2) as '成交总额',
    round(sum(p.payment_value) / count(distinct p.order_id), 2) as '客单价'
from olist_order_payments_dataset p
         join olist_orders_dataset o
              on p.order_id = o.order_id
where o.order_status = 'delivered'
group by p.payment_type
order by round(sum(p.payment_value), 2) desc;

/*
支付结构分析结论：
平台交易和收入高度依赖信用卡支付。信用卡不仅贡献了绝大多数已完成订单与 gmv，
同时具备最高 aov，说明其对应客户的消费能力或支付意愿更强；
boleto 为第二大支付方式，voucher 则更多出现在低金额支付场景。
*/

-- =============================================
-- 8. 信用卡分期结构
-- 看分期订单数与平均订单金额
-- =============================================

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
)
select
    case
        when payment_installments = 1 then '1. 单期'
        when payment_installments between 2 and 5 then '2. 低分期（2-5期）'
        when payment_installments between 6 and 10 then '3. 中分期（6-10期）'
        when payment_installments > 10 then '4. 高分期（10期以上）'
        else '未知'
        end as 分期档位,
    count(*) as 订单数,
    round(avg(order_payment_value), 2) as 平均订单金额
from credit_card_order
group by 分期档位
order by 分期档位;

/*
分期结构结论：
信用卡支付主要集中在 1 期和 2-5 期，中低分期是主流。
随着分期数上升，平均订单金额明显提高，说明更高分期通常对应更高金额订单。
*/
