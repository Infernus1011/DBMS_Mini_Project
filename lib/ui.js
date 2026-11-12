export const money = (n) => "₹" + Number(n ?? 0).toLocaleString("en-IN", { maximumFractionDigits: 2 });
export const when = (d) => (d ? new Date(d).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }) : "-");
export const Badge = ({ s }) => <span className={`badge ${s}`}>{String(s).replace("_", " ")}</span>;
