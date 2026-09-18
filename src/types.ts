export type Professional={id:string;name:string;active:boolean;display_order:number}
export type Customer={id:string;name:string;phone:string|null;email:string|null;notes:string|null;active:boolean}
export type Service={id:string;name:string;description:string|null;duration_minutes:number;price:number;active:boolean}
export type AppointmentStatus='scheduled'|'confirmed'|'in_progress'|'completed'|'cancelled'|'no_show'
export type Appointment={id:string;customer_id:string;professional_id:string;service_id:string|null;appointment_date:string;start_time:string;end_time:string;notes:string|null;status:AppointmentStatus;created_by:string;created_at:string;updated_at:string;customer?:Customer;professional?:Professional;service?:Service;creator?:{name:string|null}}
export const statusLabel:Record<AppointmentStatus,string>={scheduled:'Agendado',confirmed:'Confirmado',in_progress:'Em atendimento',completed:'Concluído',cancelled:'Cancelado',no_show:'Não compareceu'}